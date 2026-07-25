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

.PHONY: build build-debug bundle install run dev clean test log emoji-keywords verify-sign

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
	@for b in $(BUILD_DIR)/release/*.bundle; do \
		[ -d "$$b" ] && cp -R "$$b" "$(BUNDLE_DIR)/Contents/Resources/"; \
		if [ -d "$$b" ] && [ -f "$$b/Info.plist" ]; then \
			cp -R "$$b" "$(BUNDLE_DIR)/Contents/MacOS/"; \
		fi; \
	done
	@# ネストしたリソースバンドルを内側から先に署名する (ルートを先に署名すると seal violation)。
	@# Info.plist を持たない .bundle は codesign から見るとバンドルではないので除外する。
	@find "$(BUNDLE_DIR)/Contents" -depth -name "*.bundle" -type d \
		| while IFS= read -r nested; do \
			[ -f "$$nested/Info.plist" ] || continue; \
			codesign --force --sign "$(CODESIGN_IDENTITY)" "$$nested"; \
		done
	@codesign --force --sign "$(CODESIGN_IDENTITY)" --entitlements "$(ENTITLEMENTS)" "$(BUNDLE_DIR)"
	@echo "Signed with: $(CODESIGN_IDENTITY)"
	@echo "Bundle created: $(BUNDLE_DIR)"

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
	@for b in $(BUILD_DIR)/debug/*.bundle; do \
		[ -d "$$b" ] && cp -R "$$b" "$(BUNDLE_DIR)/Contents/Resources/"; \
		if [ -d "$$b" ] && [ -f "$$b/Info.plist" ]; then \
			cp -R "$$b" "$(BUNDLE_DIR)/Contents/MacOS/"; \
		fi; \
	done
	@# ネストしたリソースバンドルを内側から先に署名する (ルートを先に署名すると seal violation)。
	@# Info.plist を持たない .bundle は codesign から見るとバンドルではないので除外する。
	@find "$(BUNDLE_DIR)/Contents" -depth -name "*.bundle" -type d \
		| while IFS= read -r nested; do \
			[ -f "$$nested/Info.plist" ] || continue; \
			codesign --force --sign "$(CODESIGN_IDENTITY)" "$$nested"; \
		done
	@codesign --force --sign "$(CODESIGN_IDENTITY)" --entitlements "$(ENTITLEMENTS)" "$(BUNDLE_DIR)"
	@echo "Signed with: $(CODESIGN_IDENTITY)"
	@"$(BUNDLE_DIR)/Contents/MacOS/$(EXEC_NAME)"

log:
	@echo "Streaming logs for $(BUNDLE_ID)... (Ctrl+C to stop)"
	@log stream --predicate 'subsystem == "$(BUNDLE_ID)"' --level debug

clean:
	swift package clean
	@rm -rf "$(BUILD_DIR)/$(APP_NAME).app"
