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
# The app to package and the disk image to write (`make dmg`, also used by release.yml).
APP ?= $(BUILD_DIR)/JblOnMac.app
DMG ?= $(BUILD_DIR)/JblOnMac.dmg
# A blank disk image with the installer window already laid out (see the dmg target).
DMG_TEMPLATE ?= InstallerTemplate.dmg

# ── xcodebuild ───────────────────────────────────────────────────────────────

APP_SCHEME := JblOnMac
TEST_SCHEME := JblOnMacTests
XCODEBUILD_FLAGS := -project JblOnMac.xcodeproj -destination 'platform=macOS' -derivedDataPath $(BUILD_DIR)
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
SHARD_SOURCES = $(if $(filter root,$(TEST_SHARD)),$(wildcard JblOnMacTests/*Tests.swift),$(shell find JblOnMacTests/$(TEST_SHARD) -name '*Tests.swift'))
# The suites in the shard, one `JblOnMacTests/<Suite>` per line, for -only-testing.
SHARD_TEST_LIST := $(BUILD_DIR)/shard-$(TEST_SHARD).txt
SUITE_PATTERN := '^(struct|final class) [A-Za-z0-9]+Tests|^extension ControllerSuite'
ONLY_TESTING_FLAGS := $(if $(TEST_SHARD),-only-testing @$(SHARD_TEST_LIST))

# ── DMG ──────────────────────────────────────────────────────────────────────

APP_NAME := $(notdir $(APP))
# A writable copy of the template, and where it is mounted while the app is copied in.
DMG_STAGING_IMAGE := $(BUILD_DIR)/dmg-work.dmg
DMG_MOUNT_POINT := $(BUILD_DIR)/dmg-work

# ── Targets ──────────────────────────────────────────────────────────────────

.PHONY: check lint format analyze periphery build build-for-testing test dmg

# Runs every step even if one fails, then reports the failures.
check:
	@$(MAKE) --no-print-directory -k lint format build test analyze periphery

# ── Static checks ────────────────────────────────────────────────────────────

lint:
	swiftlint lint --strict --quiet

format:
	swiftformat --lint .

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
	$(if $(TEST_SHARD),grep -hoE $(SUITE_PATTERN) $(SHARD_SOURCES) \
		| awk '{ print "JblOnMacTests/" $$NF }' | sort -u > $(SHARD_TEST_LIST))
	set -o pipefail; xcodebuild test $(XCODEBUILD_FLAGS) -scheme $(TEST_SCHEME) -enableCodeCoverage $(COVERAGE) \
		$(TEST_TIMEOUT_FLAGS) -resultBundlePath $(TEST_RESULT) $(SIGNING_FLAGS) $(ONLY_TESTING_FLAGS) \
		| tee $(TEST_LOG)

# ── Packaging ────────────────────────────────────────────────────────────────

# Copies the built app into a copy of DMG_TEMPLATE, which holds the installer window layout.
# Finder saves that layout per file name, so the app must be named JblOnMac.app.
dmg:
	mkdir -p $(DMG_MOUNT_POINT)
	hdiutil convert "$(DMG_TEMPLATE)" -quiet -ov -format UDRW -o $(DMG_STAGING_IMAGE)
	hdiutil attach $(DMG_STAGING_IMAGE) -quiet -noautoopen -nobrowse -mountpoint $(DMG_MOUNT_POINT)
	@# The template holds an empty placeholder app, which ditto would merge into instead of replace.
	rm -rf "$(DMG_MOUNT_POINT)/$(APP_NAME)"
	ditto "$(APP)" "$(DMG_MOUNT_POINT)/$(APP_NAME)"
	hdiutil detach $(DMG_MOUNT_POINT) -quiet || { sleep 2; hdiutil detach $(DMG_MOUNT_POINT) -force -quiet; }
	hdiutil convert $(DMG_STAGING_IMAGE) -quiet -ov -format UDZO -imagekey zlib-level=9 -o "$(DMG)"
	rm -rf $(DMG_MOUNT_POINT) $(DMG_STAGING_IMAGE)
	shasum -a 256 "$(DMG)" > "$(DMG).sha256"
