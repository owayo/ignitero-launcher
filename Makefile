APP_NAME := IgniteroLauncher
EXEC_NAME := IgniteroLauncher
BUNDLE_ID := com.owayo.ignitero.launcher
BUILD_DIR := .build
RELEASE_BIN := $(BUILD_DIR)/release/$(EXEC_NAME)
DEBUG_BIN := $(BUILD_DIR)/debug/$(EXEC_NAME)
BUNDLE_DIR := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR := /Applications
EMOJI_KEYWORDS := Sources/IgniteroCore/Resources/emoji_keywords_ja.json
ENTITLEMENTS := Resources/$(APP_NAME).entitlements
# Swift 6.3.2 の release 最適化で KeyboardShortcuts 3.0.0 のコンパイル中に
# swift-frontend がクラッシュするため、最適化だけを無効化して release 出力を生成する。
RELEASE_SWIFT_FLAGS := -Xswiftc -Onone

# ad-hoc 署名 (--sign -) は再ビルドのたびに cdhash が変わるため、TCC が
# 「別アプリ」と見なしてアクセシビリティ権限が毎回無効化される (設定のチェックは
# 残るので「許可しているのに Option+Space が効かない」という壊れ方をする)。
# ローカルの自己署名 identity があればそれで固定し、無い環境 (CI・他マシン) では
# ad-hoc に fallback してビルドが止まらないようにする。
CODESIGN_IDENTITY ?= $(shell \
	if security find-identity -v -p codesigning 2>/dev/null | grep -qF "owayo local dev"; \
	then echo "owayo local dev"; else echo "-"; fi)

# `.app` に必ず入っていなければならない SwiftPM のリソースバンドル。
# `Bundle.module` は `.app` では解決できない (探索先が `.app/` ルート直下と
# ビルド時に焼き込まれた `.build` の絶対パスの 2 つだけで、`Contents/Resources` を
# 見ない。ルート直下は codesign が unsealed contents として拒否する) ため、
# リソースは `ResourceBundle.resolve(named:)` が読む `Contents/Resources` に置く。
# ここに配置漏れがあると絵文字のローカライズ名とキーワード辞書が黙って失われる。
#
# バンドルのディレクトリ有無ではなく代表ファイルの有無で見る。`Bundle(url:)` は
# 空ディレクトリでも成功するため、中身が欠けた `.bundle` があると解決自体は通って
# しまい、機能だけが無音で消える。
REQUIRED_RESOURCES := \
	EmojiKit_EmojiKit.bundle/ja.lproj/Localizable.strings \
	IgniteroLauncher_IgniteroCore.bundle/emoji_keywords_ja.json

.PHONY: build build-debug bundle install run dev clean test log emoji-keywords verify-sign verify-bundle smoke-resources

emoji-keywords:
	@python3 scripts/update_emoji_keywords.py

build: emoji-keywords
	swift build -c release $(RELEASE_SWIFT_FLAGS)

build-debug:
	swift build -c debug

test:
	swift test

bundle: build
	@rm -rf "$(BUNDLE_DIR)"
	@mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	@cp "$(RELEASE_BIN)" "$(BUNDLE_DIR)/Contents/MacOS/$(EXEC_NAME)"
	@cp "Resources/Info.plist" "$(BUNDLE_DIR)/Contents/Info.plist"
	@cp "Resources/AppIcon.icns" "$(BUNDLE_DIR)/Contents/Resources/AppIcon.icns"
	@cp "Resources/MenuBarIcon.png" "$(BUNDLE_DIR)/Contents/Resources/MenuBarIcon.png"
	@cp "Resources/MenuBarIcon@2x.png" "$(BUNDLE_DIR)/Contents/Resources/MenuBarIcon@2x.png"
	@cp "Resources/IgniteroLauncher.entitlements" "$(BUNDLE_DIR)/Contents/Resources/"
	@# リソースバンドルは Contents/Resources にのみ置く。ResourceBundle.resolve(named:)
	@# がここを読む。Contents/MacOS へのコピーはどの探索経路からも参照されない
	@# (Bundle.main.resourceURL / url(forResource:) / Bundle(for:).resourceURL /
	@# SwiftPM の accessor のいずれも見ない) ため、署名対象とサイズを増やすだけだった。
	@for b in $(BUILD_DIR)/release/*.bundle; do \
		[ -d "$$b" ] || continue; \
		cp -R "$$b" "$(BUNDLE_DIR)/Contents/Resources/"; \
	done
	@# ネストしたリソースバンドルを内側から先に署名する (ルートを先に署名すると seal violation)。
	@# Info.plist を持たない .bundle は codesign から見るとバンドルではないので除外する。
	@find "$(BUNDLE_DIR)/Contents" -depth -name "*.bundle" -type d \
		| while IFS= read -r nested; do \
			[ -f "$$nested/Info.plist" ] || continue; \
			codesign --force --sign "$(CODESIGN_IDENTITY)" "$$nested"; \
		done
	@codesign --force --sign "$(CODESIGN_IDENTITY)" --entitlements "$(ENTITLEMENTS)" "$(BUNDLE_DIR)"
	@$(MAKE) --no-print-directory verify-bundle
	@echo "Signed with: $(CODESIGN_IDENTITY)"
	@echo "Bundle created: $(BUNDLE_DIR)"

# `.app` に必要なリソースが揃っているか、バージョンが一意かを検証する。
verify-bundle:
	@# SwiftPM のリソースバンドルは配置が 2 通りある。
	@#   flat          : <name>.bundle/ja.lproj/Localizable.strings
	@#   macOS バンドル: <name>.bundle/Contents/Resources/ja.lproj/Localizable.strings
	@# どちらになるかはビルドシステム (debug/release) と SwiftPM の版で変わる
	@# (2026-09-22 時点で debug は flat、release は Contents/Resources)。
	@# 読み出しは Bundle API 経由なのでどちらでも解決できるため、検証も両方を許容する。
	@for r in $(REQUIRED_RESOURCES); do \
		bundle_name="$${r%%/*}"; \
		rel="$${r#*/}"; \
		base="$(BUNDLE_DIR)/Contents/Resources/$$bundle_name"; \
		if [ ! -e "$$base/$$rel" ] && [ ! -e "$$base/Contents/Resources/$$rel" ]; then \
			echo "error: $$rel が $$base (直下または Contents/Resources) に無い" >&2; \
			echo "       ResourceBundle.resolve(named:) が中身を読めず、絵文字のローカライズ名や" >&2; \
			echo "       キーワード辞書が黙って失われる。bundle ターゲットの配置処理を確認する。" >&2; \
			exit 1; \
		fi; \
	done
	@echo "Resource bundles: OK"
	@# バージョンの正本は Info.plist の CFBundleShortVersionString ただ 1 つ
	@# (release.yml が bump するのもここだけ)。アプリが別の値を自己申告すると
	@# アップデート判定が誤ったバージョンで行われ、通知が出なくなる。
	@# source plist → bundle へのコピー → 実行時の Bundle.main 解決までを一度に検査する。
	@plist_version="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
		"$(BUNDLE_DIR)/Contents/Info.plist")"; \
	reported_version="$$("$(BUNDLE_DIR)/Contents/MacOS/$(EXEC_NAME)" --print-version)" || { \
		echo "error: アプリがバージョンを申告できなかった" >&2; exit 1; }; \
	if [ "$$plist_version" != "$$reported_version" ]; then \
		echo "error: バージョン不一致 (Info.plist=$$plist_version / アプリ=$$reported_version)" >&2; \
		echo "       Info.plist を唯一の正本にする。Swift 側に定数を置かない。" >&2; \
		exit 1; \
	fi; \
	echo "Version: $$plist_version"

# `.app` を実際に起動してリソース解決の自己診断を行う。
# ビルドディレクトリの `.bundle` を退避して `Bundle.module` の fallback を無効化するため、
# 「開発マシンでは動くが `.build` を消すと落ちる」破損を検出できる。
smoke-resources: bundle
	@bash scripts/smoke_resources.sh "$(BUNDLE_DIR)" "$(EXEC_NAME)"

install: bundle
	@osascript -e 'quit app "$(APP_NAME)"' 2>/dev/null || true
	@sleep 1
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(BUNDLE_DIR)" "$(INSTALL_DIR)/"
	@touch "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"
	@open "$(INSTALL_DIR)/$(APP_NAME).app"

run: bundle
	@open "$(BUNDLE_DIR)"

# 「権限を許可しているのに Option+Space が効かない」ときに、署名が ad-hoc へ
# fallback していないかを確認する。Authority=owayo local dev なら固定署名。
verify-sign:
	@codesign --verify --strict --verbose=2 "$(INSTALL_DIR)/$(APP_NAME).app"
	@codesign -dv --verbose=2 "$(INSTALL_DIR)/$(APP_NAME).app" 2>&1 \
		| grep -e '^Identifier=' -e '^Authority=' -e '^Signature='

dev: build-debug
	@rm -rf "$(BUNDLE_DIR)"
	@mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	@cp "$(DEBUG_BIN)" "$(BUNDLE_DIR)/Contents/MacOS/$(EXEC_NAME)"
	@cp "Resources/Info.plist" "$(BUNDLE_DIR)/Contents/Info.plist"
	@cp "Resources/AppIcon.icns" "$(BUNDLE_DIR)/Contents/Resources/AppIcon.icns"
	@cp "Resources/MenuBarIcon.png" "$(BUNDLE_DIR)/Contents/Resources/MenuBarIcon.png"
	@cp "Resources/MenuBarIcon@2x.png" "$(BUNDLE_DIR)/Contents/Resources/MenuBarIcon@2x.png"
	@cp "Resources/IgniteroLauncher.entitlements" "$(BUNDLE_DIR)/Contents/Resources/"
	@# 配置方針は bundle ターゲットと同じ (Contents/Resources のみ)。
	@for b in $(BUILD_DIR)/debug/*.bundle; do \
		[ -d "$$b" ] || continue; \
		cp -R "$$b" "$(BUNDLE_DIR)/Contents/Resources/"; \
	done
	@# ネストしたリソースバンドルを内側から先に署名する (ルートを先に署名すると seal violation)。
	@# Info.plist を持たない .bundle は codesign から見るとバンドルではないので除外する。
	@find "$(BUNDLE_DIR)/Contents" -depth -name "*.bundle" -type d \
		| while IFS= read -r nested; do \
			[ -f "$$nested/Info.plist" ] || continue; \
			codesign --force --sign "$(CODESIGN_IDENTITY)" "$$nested"; \
		done
	@codesign --force --sign "$(CODESIGN_IDENTITY)" --entitlements "$(ENTITLEMENTS)" "$(BUNDLE_DIR)"
	@$(MAKE) --no-print-directory verify-bundle
	@echo "Signed with: $(CODESIGN_IDENTITY)"
	@"$(BUNDLE_DIR)/Contents/MacOS/$(EXEC_NAME)"

log:
	@echo "Streaming logs for $(BUNDLE_ID)... (Ctrl+C to stop)"
	@log stream --predicate 'subsystem == "$(BUNDLE_ID)"' --level debug

clean:
	swift package clean
	@rm -rf "$(BUILD_DIR)/$(APP_NAME).app"
