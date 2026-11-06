#!/usr/bin/env bash
# Checks that a built app has a valid signature and the expected version, and prints its
# entitlements for the log.
#
# Usage: Scripts/codesign.sh <app> <version>
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <app> <version>" >&2
  exit 2
fi
app=$1 expected=$2

codesign --verify --deep --strict --verbose=2 "$app"
codesign --display --entitlements - "$app"

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
if [[ "$version" != "$expected" ]]; then
  echo "Built version $version, expected $expected" >&2
  exit 1
fi
echo "$app is signed and has version $version"
