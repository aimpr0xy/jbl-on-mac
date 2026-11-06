# Same gates as CI (lint.yml, format.yml, test.yml, quality.yml in .github/workflows).
# Run `make check` before every commit.

# ── Settings ─────────────────────────────────────────────────────────────────

# Recipes use `set -o pipefail`.
SHELL := /bin/bash
BUILD_DIR := build

# ── Inputs (override on the command line) ───────────────────────────────────

# A top-level folder of JblOnMacTests, or root for the files directly in it, to run only its tests.
TEST_SHARD ?=
# Collects coverage data in the result bundle. CI sets NO.
COVERAGE ?= YES
# The part of the version `make next-version` increases: patch, minor or major.
BUMP ?= patch
# The version and build number `make archive` stamps on the app. Empty keeps the project's values.
VERSION ?=
BUILD_NUMBER ?=
# The app to verify and package, and the disk image to write.
APP ?= $(BUILD_DIR)/JblOnMac.app
DMG ?= $(BUILD_DIR)/JblOnMac.dmg
# A blank disk image with the installer window already laid out (see Scripts/hdiutil.sh).
DMG_TEMPLATE ?= InstallerTemplate.dmg

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

# ── Tests ────────────────────────────────────────────────────────────────────

TEST_RESULT := $(BUILD_DIR)/tests$(if $(TEST_SHARD),-$(TEST_SHARD)).xcresult
TEST_LOG := $(TEST_RESULT:.xcresult=.log)
# The suites in the shard, one `JblOnMacTests/<Suite>` per line, for -only-testing.
SHARD_TEST_LIST := $(BUILD_DIR)/shard-$(TEST_SHARD).txt
ONLY_TESTING_FLAGS := $(if $(TEST_SHARD),-only-testing @$(SHARD_TEST_LIST))

# ── Release ──────────────────────────────────────────────────────────────────

ARCHIVE := $(BUILD_DIR)/JblOnMac.xcarchive
ARCHIVE_LOG := $(BUILD_DIR)/archive.log
# Ad-hoc signing ("-") still embeds the sandbox and Bluetooth entitlements.
RELEASE_SIGNING_FLAGS := CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES \
	CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
VERSION_FLAGS := $(if $(VERSION),MARKETING_VERSION=$(VERSION)) \
	$(if $(BUILD_NUMBER),CURRENT_PROJECT_VERSION=$(BUILD_NUMBER))

# ── Targets ──────────────────────────────────────────────────────────────────

.PHONY: check lint format shellcheck analyze periphery build build-for-testing test \
	next-version archive verify-app dmg

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

# Needs `make build-for-testing` first for the index store.
periphery:
	periphery scan

# ── Build and test ───────────────────────────────────────────────────────────

# A clean build is needed so the compiler log lists every file for `swiftlint analyze`.
build:
	rm -rf $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)
	set -o pipefail; xcodebuild clean build $(XCODEBUILD_FLAGS) -scheme $(APP_SCHEME) $(SIGNING_FLAGS) \
		| tee $(BUILD_LOG)

# Indexes the test target too, which Periphery needs, without running any test.
build-for-testing:
	set -o pipefail; xcodebuild build-for-testing $(XCODEBUILD_FLAGS) -scheme $(TEST_SCHEME) $(SIGNING_FLAGS) \
		| tee $(TESTING_BUILD_LOG)

test:
	rm -rf $(TEST_RESULT)
	mkdir -p $(BUILD_DIR)
	@# The test target doesn't declare its dependency on the app, so build the app first.
	xcodebuild build -quiet $(XCODEBUILD_FLAGS) -scheme $(APP_SCHEME) $(SIGNING_FLAGS)
	$(if $(TEST_SHARD),Scripts/test-shard-suites.sh $(TEST_SHARD) > $(SHARD_TEST_LIST))
	set -o pipefail; xcodebuild test $(XCODEBUILD_FLAGS) -scheme $(TEST_SCHEME) -enableCodeCoverage $(COVERAGE) \
		$(TEST_TIMEOUT_FLAGS) -resultBundlePath $(TEST_RESULT) $(SIGNING_FLAGS) $(ONLY_TESTING_FLAGS) \
		| tee $(TEST_LOG)

# ── Release (release.yml runs these in order) ────────────────────────────────

# Prints the tag the next release gets, from the latest v* tag.
next-version:
	@Scripts/semver.sh $(BUMP)

# Builds the Release configuration, ad-hoc signed, and copies the app to APP.
archive:
	mkdir -p $(BUILD_DIR)
	set -o pipefail; xcodebuild archive -project $(PROJECT) -scheme $(APP_SCHEME) -configuration Release \
		-destination 'generic/platform=macOS' -archivePath $(ARCHIVE) $(RELEASE_SIGNING_FLAGS) $(VERSION_FLAGS) \
		| tee $(ARCHIVE_LOG)
	rm -rf "$(APP)"
	cp -R $(ARCHIVE)/Products/Applications/$(notdir $(APP)) "$(APP)"

verify-app:
	$(if $(VERSION),,$(error Set VERSION to the version the app should have))
	Scripts/codesign.sh "$(APP)" $(VERSION)

dmg:
	Scripts/hdiutil.sh "$(DMG_TEMPLATE)" "$(APP)" "$(DMG)"
