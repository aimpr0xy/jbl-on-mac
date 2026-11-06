#!/usr/bin/env bash
# Downloads a release archive, checks its SHA-256 and unpacks it into a folder. CI installs its tools
# with it, so every run uses the same pinned versions.
#
# Usage: Scripts/install-tool.sh <url of a .zip or .tar.gz> <sha256> <folder>
#
# A .tar.gz archive's top-level folder is dropped, so the tool lands directly in <folder>.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <url of a .zip or .tar.gz> <sha256> <folder>" >&2
  exit 2
fi
url=$1 sha256=$2 folder=$3

archive=$(mktemp)
trap 'rm -f "$archive"' EXIT
curl -fsSL --retry 3 -o "$archive" "$url"

if ! echo "$sha256  $archive" | shasum -a 256 -c - > /dev/null 2>&1; then
  echo "SHA-256 of $url is $(shasum -a 256 "$archive" | cut -d ' ' -f 1), expected $sha256" >&2
  exit 1
fi

mkdir -p "$folder"
case "$url" in
  *.zip) unzip -q -o "$archive" -d "$folder" ;;
  *.tar.gz) tar -xzf "$archive" -C "$folder" --strip-components 1 ;;
  *)
    echo "Unsupported archive type: $url" >&2
    exit 1
    ;;
esac
echo "Installed $(basename "$url") in $folder"
