#!/usr/bin/env bash
# Prints the test suites in one shard of the tests, one `JblOnMacTests/<Suite>` per line, for
# xcodebuild's -only-testing. A shard is a top-level folder of the tests folder, or root for the
# files directly in it. CI runs one shard per job (the matrix in test.yml).
#
# Usage: Scripts/test-shard-suites.sh <shard> [tests folder, default JblOnMacTests]
#
# A suite is a top-level `struct` or `final class` named *Tests in a *Tests.swift file. Suites that
# extend ControllerSuite run through it, so a file with `extension ControllerSuite` adds that suite.
set -euo pipefail

shard=${1:-}
tests=${2:-JblOnMacTests}
if [[ -z "$shard" ]]; then
  echo "Usage: $0 <shard> [tests folder]" >&2
  exit 2
fi

if [[ "$shard" == root ]]; then
  folder=$tests
  depth=(-maxdepth 1)
elif [[ -d "$tests/$shard" ]]; then
  folder="$tests/$shard"
  depth=()
else
  echo "No test folder $tests/$shard" >&2
  exit 1
fi

pattern='^(struct|final class) [A-Za-z0-9]+Tests|^extension ControllerSuite'
# grep exits 1 for a file without a suite, which isn't an error here.
suites=$(
  { find "$folder" ${depth[@]+"${depth[@]}"} -type f -name '*Tests.swift' -exec grep -hoE "$pattern" {} + || true; } \
    | awk '{ print "JblOnMacTests/" $NF }' | sort -u
)

if [[ -z "$suites" ]]; then
  echo "No test suites in $folder" >&2
  exit 1
fi
echo "$suites"
