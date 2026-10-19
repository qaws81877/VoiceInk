# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
# The .noindex suffix keeps Spotlight from listing every built copy of the app.
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build.noindex
DEV_DERIVED_DATA := $(CURDIR)/.build.noindex
TEST_DERIVED_DATA := $(CURDIR)/.test-build.noindex
LOCAL_CODESIGN_IDENTITY ?=
RUN_APP_NAME ?= Sulsul

# Shell fragment used by local: sets SIGNING_IDENTITY to the single
# Apple Development identity (or LOCAL_CODESIGN_IDENTITY), else "-" for ad-hoc.
# A stable identity keeps the designated requirement, so TCC permissions survive rebuilds.
RESOLVE_SIGNING_IDENTITY = SIGNING_IDENTITY="$(LOCAL_CODESIGN_IDENTITY)"; \
	if [ -z "$$SIGNING_IDENTITY" ]; then \
		SIGNING_IDENTITIES=$$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development: / { print $$2 }'); \
		SIGNING_IDENTITY_COUNT=$$(printf '%s\n' "$$SIGNING_IDENTITIES" | awk 'NF { count++ } END { print count + 0 }'); \
		if [ "$$SIGNING_IDENTITY_COUNT" -eq 1 ]; then \
			SIGNING_IDENTITY=$$(printf '%s\n' "$$SIGNING_IDENTITIES" | awk 'NF { print; exit }'); \
		elif [ "$$SIGNING_IDENTITY_COUNT" -gt 1 ]; then \
			echo "Multiple Apple Development identities found; set LOCAL_CODESIGN_IDENTITY to choose one; using ad-hoc signing"; \
		fi; \
	fi; \
	if [ -n "$$SIGNING_IDENTITY" ] && [ "$$SIGNING_IDENTITY" != "-" ]; then \
		SIGNING_REQUIRED=YES; \
		echo "Using stable local signing identity: $$SIGNING_IDENTITY"; \
	else \
		SIGNING_IDENTITY="-"; \
		SIGNING_REQUIRED=NO; \
		echo "Using ad-hoc signing (permissions may need approval after rebuilds)"; \
	fi;

# Prints the certificate an app is signed with, or a warning when it is ad-hoc signed.
# Usage: $(call VERIFY_SIGNATURE,<path to .app>)
define VERIFY_SIGNATURE
	@AUTHORITY=$$(codesign -dvv "$(1)" 2>&1 | awk -F= '/^Authority=/ { print $$2; exit }'); \
	if [ -n "$$AUTHORITY" ]; then \
		echo "Signature check: $(notdir $(1)) is signed by $$AUTHORITY"; \
	else \
		echo ""; \
		echo "WARNING: $(notdir $(1)) is not signed with a certificate (ad-hoc)."; \
		echo "WARNING: macOS will ask for microphone and accessibility permissions again."; \
		echo "WARNING: Check 'security find-identity -v -p codesigning' or set LOCAL_CODESIGN_IDENTITY."; \
		echo ""; \
	fi
endef

.PHONY: all clean whisper setup build test local check healthcheck help dev run release release-setup

# Default target
all: check build

# Development workflow
dev: RUN_APP_NAME = Sulsul Dev
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" \
		-derivedDataPath "$(DEV_DERIVED_DATA)" \
		-skipPackagePluginValidation \
		-skipMacroValidation \
		build

# Unit tests, ad-hoc signed: the Debug entitlements need a provisioning profile.
# Separate derived data, so the LOCAL_BUILD test host never replaces Sulsul Dev.app.
test: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY=- \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		-derivedDataPath "$(TEST_DERIVED_DATA)" \
		-skipPackagePluginValidation \
		-skipMacroValidation \
		-only-testing:VoiceInkTests \
		test

# Build locally with stable Apple Development signing when available.
local: check setup
	@echo "Building 술술 (Sulsul) for local use (no Apple Developer certificate required)..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	@$(RESOLVE_SIGNING_IDENTITY) \
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="$$SIGNING_IDENTITY" \
		CODE_SIGNING_REQUIRED="$$SIGNING_REQUIRED" \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		-skipPackagePluginValidation \
		-skipMacroValidation \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Release/Sulsul.app" && \
	if [ -d "$$APP_PATH" ]; then \
		echo "Copying Sulsul.app to ~/Downloads..."; \
		rm -rf "$$HOME/Downloads/Sulsul.app"; \
		ditto "$$APP_PATH" "$$HOME/Downloads/Sulsul.app"; \
		xattr -cr "$$HOME/Downloads/Sulsul.app"; \
		rm -rf "$$APP_PATH"; \
		echo ""; \
		echo "Build complete! App saved to: ~/Downloads/Sulsul.app"; \
		echo "Run with: open ~/Downloads/Sulsul.app"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - iCloud dictionary sync is off"; \
		echo "  - Automatic updates stay off until a Sparkle key is set (see BUILDING.md)"; \
	else \
		echo "Error: Could not find built Sulsul.app at $$APP_PATH"; \
		exit 1; \
	fi
	$(call VERIFY_SIGNATURE,$(HOME)/Downloads/Sulsul.app)

# Run application
run:
	@if [ -d "$$HOME/Downloads/$(RUN_APP_NAME).app" ]; then \
		echo "Opening ~/Downloads/$(RUN_APP_NAME).app..."; \
		open "$$HOME/Downloads/$(RUN_APP_NAME).app"; \
	else \
		echo "Looking for $(RUN_APP_NAME).app in $(DEV_DERIVED_DATA)..."; \
		APP_PATH=$$(find "$(DEV_DERIVED_DATA)/Build/Products" -name "$(RUN_APP_NAME).app" -type d -maxdepth 2 2>/dev/null | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "$(RUN_APP_NAME).app not found. Build it with 'make local' or use 'make dev' for the development app."; \
			exit 1; \
		fi; \
	fi

# Build a signed, notarized DMG and matching local Sparkle Appcast.
release: whisper
	@if [ -n "$(NOTES)" ]; then \
		./scripts/release.sh --notes "$(NOTES)" $(RELEASE_ARGS); \
	else \
		./scripts/release.sh $(RELEASE_ARGS); \
	fi

# Store Apple's notarization credentials securely in Keychain.
release-setup:
	@./scripts/setup-release-notarization.sh

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Prepare whisper.xcframework for the Sulsul project"
	@echo "  build              Build the Xcode project (scheme VoiceInk, product Sulsul Dev)"
	@echo "  test               Run VoiceInkTests (ad-hoc signed)"
	@echo "  local              Build locally with stable signing when available"
	@echo "    LOCAL_CODESIGN_IDENTITY=<SHA or name> overrides automatic Apple Development detection"
	@echo "  run                Launch the built Sulsul app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  release            Build DMG and Appcast using release-notes/<version>.html"
	@echo "  release-setup      Store notarization credentials in Keychain"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
