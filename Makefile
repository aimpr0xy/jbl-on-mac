# Same gates as CI (lint.yml, format.yml, test.yml, quality.yml in .github/workflows). Run `make check` before every commit.
SIGNING = CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
XCODEBUILD = -project JblOnMac.xcodeproj -destination 'platform=macOS' -derivedDataPath build
# A top-level folder of JblOnMacTests, or root for the files directly in it, to run only its tests.
TEST_SHARD ?=
SHARD_FILES = $(if $(filter root,$(TEST_SHARD)),$(wildcard JblOnMacTests/*Tests.swift),$(shell find JblOnMacTests/$(TEST_SHARD) -name '*Tests.swift'))
# Collects coverage data in the result bundle. CI sets NO.
COVERAGE ?= YES
RESULT ?= build/tests$(if $(TEST_SHARD),-$(TEST_SHARD)).xcresult

.PHONY: check lint format build build-for-testing test analyze periphery

# Runs every step even if one fails, then reports the failures.
check:
	@$(MAKE) --no-print-directory -k lint format build test analyze periphery

lint:
	swiftlint lint --strict --quiet

format:
	swiftformat --lint .

# A clean build is needed so the compiler log lists every file for `swiftlint analyze`.
build:
	rm -rf build
	mkdir -p build
	set -o pipefail; xcodebuild clean build $(XCODEBUILD) -scheme JblOnMac $(SIGNING) | tee build/xcodebuild.log

# Indexes the test target too, which Periphery needs, without running any test.
build-for-testing:
	set -o pipefail; xcodebuild build-for-testing $(XCODEBUILD) -scheme JblOnMacTests $(SIGNING) | tee build/build-for-testing.log

# A hung test fails after the time allowance instead of stalling the run.
test:
	rm -rf $(RESULT)
	mkdir -p build
	@# The test target doesn't declare its dependency on the app, so build the app first.
	xcodebuild build -quiet $(XCODEBUILD) -scheme JblOnMac $(SIGNING)
	$(if $(TEST_SHARD),grep -hoE '^(struct|final class) [A-Za-z0-9]+Tests|^extension ControllerSuite' $(SHARD_FILES) \
		| awk '{ print "JblOnMacTests/" $$NF }' | sort -u > build/shard-$(TEST_SHARD).txt)
	set -o pipefail; xcodebuild test $(XCODEBUILD) -scheme JblOnMacTests -enableCodeCoverage $(COVERAGE) \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
		-maximum-test-execution-time-allowance 120 \
		-resultBundlePath $(RESULT) $(SIGNING) $(if $(TEST_SHARD),-only-testing @build/shard-$(TEST_SHARD).txt) | tee $(RESULT:.xcresult=.log)

analyze:
	swiftlint analyze --strict --quiet \
		--compiler-log-path build/xcodebuild.log

periphery:
	periphery scan
