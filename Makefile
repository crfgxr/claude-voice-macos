APP_NAME = ClaudeVoice
APP_BUNDLE = $(APP_NAME).app
BUILD_DIR = $(shell swift build -c release --show-bin-path 2>/dev/null)

.PHONY: build run install clean

build:
	swift build -c release
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	@codesign --force --sign - $(APP_BUNDLE)
	@echo "Built: $(APP_BUNDLE)"

run: build
	open $(APP_BUNDLE)

install:
	chmod +x install.sh
	./install.sh

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
