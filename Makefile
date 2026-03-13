APP_NAME = ClaudeHandsFree
APP_BUNDLE = $(APP_NAME).app
INSTALL_DIR = /Applications
BUILD_DIR = $(shell swift build -c release --show-bin-path 2>/dev/null)

.PHONY: build run install clean

build:
	swift build -c release
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	@cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	@codesign --force --sign - $(APP_BUNDLE)
	@echo "Built: $(APP_BUNDLE)"

run: install
	open $(INSTALL_DIR)/$(APP_BUNDLE)

install: build
	@pkill -f "ClaudeHandsFree" 2>/dev/null || true
	@sleep 0.5
	@rm -rf $(INSTALL_DIR)/$(APP_BUNDLE)
	@cp -R $(APP_BUNDLE) $(INSTALL_DIR)/$(APP_BUNDLE)
	@echo "Installed: $(INSTALL_DIR)/$(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
