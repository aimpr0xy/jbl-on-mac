# Same gates as CI (lint.yml, format.yml, test.yml in .github/workflows). Run `make check` before every commit.
SIGNING = CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
XCODEBUILD = -project JblOnMac.xcodeproj -destination 'platform=macOS' -derivedDataPath build
RESULT = build/tests.xcresult

.PHONY: check lint format build test coverage analyze periphery

# Runs every step even if one fails, then reports the failures.
check:
	@$(MAKE) --no-print-directory -k lint format build test coverage analyze periphery

lint:
	swiftlint lint --strict --quiet

format:
	swiftformat --lint .

# A clean build is needed so the compiler log lists every file for `swiftlint analyze`.
build:
	rm -rf build
	mkdir -p build
	set -o pipefail; xcodebuild clean build $(XCODEBUILD) -scheme JblOnMac $(SIGNING) | tee build/xcodebuild.log

test:
	rm -rf $(RESULT)
	mkdir -p build
	set -o pipefail; xcodebuild test $(XCODEBUILD) -scheme JblOnMacTests -enableCodeCoverage YES \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
		-maximum-test-execution-time-allowance 120 \
		-resultBundlePath $(RESULT) $(SIGNING) | tee build/tests.log

coverage:
	swift Tools/CoverageGate.swift $(RESULT)

analyze:
	swiftlint analyze --strict --quiet \
		--compiler-log-path build/xcodebuild.log

periphery:
	periphery scan
