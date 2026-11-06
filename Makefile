# Same gates as CI (.github/workflows/ci.yml). Run `make check` before every commit.

# ── Settings ─────────────────────────────────────────────────────────────────

# Recipes use `set -o pipefail`.
SHELL := /bin/bash
BUILD_DIR := build

# ── Inputs (override on the command line) ───────────────────────────────────

# Collects coverage data in the result bundle. CI sets NO.
COVERAGE ?= YES
# The version and build number `make archive` stamps on the app. Empty keeps the project's values.
VERSION ?=
BUILD_NUMBER ?=
# Where `make archive` puts the app.
APP ?= $(BUILD_DIR)/JblOnMac.app

# ── xcodebuild ───────────────────────────────────────────────────────────────

PROJECT := JblOnMac.xcodeproj
APP_SCHEME := JblOnMac
TEST_SCHEME := JblOnMacTests
XCODEBUILD_FLAGS := -project $(PROJECT) -destination 'platform=macOS' -derivedDataPath $(BUILD_DIR)
SIGNING_FLAGS := CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
# A hung test fails after the time allowance instead of stalling the run.
TEST_TIMEOUT_FLAGS := -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
	-maximum-test-execution-time-allowance 120
# `swiftlint analyze` reads the compiler invocations from this log.
BUILD_LOG := $(BUILD_DIR)/xcodebuild.log
TESTING_BUILD_LOG := $(BUILD_DIR)/build-for-testing.log
TEST_RESULT := $(BUILD_DIR)/tests.xcresult
TEST_LOG := $(BUILD_DIR)/tests.log

# ── Release ──────────────────────────────────────────────────────────────────

ARCHIVE := $(BUILD_DIR)/JblOnMac.xcarchive
ARCHIVE_LOG := $(BUILD_DIR)/archive.log
# Ad-hoc signing ("-") still embeds the sandbox and Bluetooth entitlements.
RELEASE_SIGNING_FLAGS := CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES \
	CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
VERSION_FLAGS := $(if $(VERSION),MARKETING_VERSION=$(VERSION)) \
	$(if $(BUILD_NUMBER),CURRENT_PROJECT_VERSION=$(BUILD_NUMBER))

# ── Targets ──────────────────────────────────────────────────────────────────

.PHONY: check lint format shellcheck analyze periphery build test archive

# Runs every step even if one fails, then reports the failures.
check:
	@$(MAKE) --no-print-directory -k lint format shellcheck build test analyze periphery

# ── Static checks ────────────────────────────────────────────────────────────

lint:
	swiftlint lint --strict --quiet

format:
	swiftformat --lint .

shellcheck:
	shellcheck Scripts/*.sh

# Needs `make build` first for the compiler log.
analyze:
	swiftlint analyze --strict --quiet --compiler-log-path $(BUILD_LOG)

# Needs `make test` first for the test target's index store.
periphery:
	periphery scan

# ── Build and test ───────────────────────────────────────────────────────────

# A clean build is needed so the compiler log lists every file for `swiftlint analyze`.
build:
	rm -rf $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)
	set -o pipefail; xcodebuild clean build $(XCODEBUILD_FLAGS) -scheme $(APP_SCHEME) $(SIGNING_FLAGS) \
		| tee $(BUILD_LOG)

# Builds the tests once, which also indexes them for Periphery, then runs them on that build.
test:
	mkdir -p $(BUILD_DIR)
	rm -rf $(TEST_RESULT)
	@# The test target doesn't declare its dependency on the app, so build the app first.
	xcodebuild build -quiet $(XCODEBUILD_FLAGS) -scheme $(APP_SCHEME) $(SIGNING_FLAGS)
	set -o pipefail; xcodebuild build-for-testing $(XCODEBUILD_FLAGS) -scheme $(TEST_SCHEME) \
		-enableCodeCoverage $(COVERAGE) $(SIGNING_FLAGS) | tee $(TESTING_BUILD_LOG)
	set -o pipefail; xcodebuild test-without-building $(XCODEBUILD_FLAGS) -scheme $(TEST_SCHEME) \
		-enableCodeCoverage $(COVERAGE) $(TEST_TIMEOUT_FLAGS) -resultBundlePath $(TEST_RESULT) $(SIGNING_FLAGS) \
		| tee $(TEST_LOG)

# ── Release ──────────────────────────────────────────────────────────────────

# Builds the Release configuration, ad-hoc signed, and copies the app to APP. Used by release.yml.
archive:
	mkdir -p $(BUILD_DIR)
	set -o pipefail; xcodebuild archive -project $(PROJECT) -scheme $(APP_SCHEME) -configuration Release \
		-destination 'generic/platform=macOS' -archivePath $(ARCHIVE) $(RELEASE_SIGNING_FLAGS) $(VERSION_FLAGS) \
		| tee $(ARCHIVE_LOG)
	rm -rf "$(APP)"
	cp -R $(ARCHIVE)/Products/Applications/$(notdir $(APP)) "$(APP)"
