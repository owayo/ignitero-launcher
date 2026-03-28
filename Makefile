APP_NAME := IgniteroLauncher
EXEC_NAME := IgniteroLauncher
BUNDLE_ID := com.owayo.ignitero.launcher
BUILD_DIR := .build
RELEASE_BIN := $(BUILD_DIR)/release/$(EXEC_NAME)
DEBUG_BIN := $(BUILD_DIR)/debug/$(EXEC_NAME)
BUNDLE_DIR := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR := /Applications
EMOJI_KEYWORDS := Sources/IgniteroCore/Resources/emoji_keywords_ja.json

.PHONY: build build-debug bundle install run dev clean test log emoji-keywords

emoji-keywords:
	@python3 scripts/update_emoji_keywords.py

build: emoji-keywords
	swift build -c release

build-debug:
	swift build -c debug

test:
	swift test

bundle: build
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
	done
	@codesign --force --sign - --entitlements "Resources/IgniteroLauncher.entitlements" "$(BUNDLE_DIR)"
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

dev: build-debug
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
	done
	@codesign --force --sign - --entitlements "Resources/IgniteroLauncher.entitlements" "$(BUNDLE_DIR)"
	@"$(BUNDLE_DIR)/Contents/MacOS/$(EXEC_NAME)"

log:
	@echo "Streaming logs for $(BUNDLE_ID)... (Ctrl+C to stop)"
	@log stream --predicate 'subsystem == "$(BUNDLE_ID)"' --level debug

clean:
	swift package clean
	@rm -rf "$(BUILD_DIR)/$(APP_NAME).app"
