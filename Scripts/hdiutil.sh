#!/usr/bin/env bash
# Packages an app in an installer disk image and writes its SHA-256 file next to it.
#
# Usage: Scripts/hdiutil.sh <template.dmg> <app> <output.dmg>
#
# The template is a blank disk image with the installer window already laid out: background, disk
# icon, window size, icon size and icon positions. The app is copied into a writable copy of it, in
# place of an empty placeholder app. Finder saves the layout per file name, so the app must have the
# placeholder's name (JblOnMac.app). It needs only hdiutil, ditto and shasum, which ship with macOS.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <template.dmg> <app> <output.dmg>" >&2
  exit 2
fi
template=$1 app=$2 dmg=$3
app_name=$(basename "$app")
[[ -f "$template" ]] || { echo "No disk image template at $template" >&2; exit 1; }
[[ -d "$app" ]] || { echo "No app at $app" >&2; exit 1; }

work=$(mktemp -d)
staging="$work/staging.dmg"
mount_point="$work/mount"
mounted=false

detach() {
  hdiutil detach "$mount_point" -quiet || { sleep 2; hdiutil detach "$mount_point" -force -quiet; }
  mounted=false
}
# Leaves no image mounted and no temporary files, also when a step fails.
cleanup() {
  if [[ "$mounted" == true ]]; then detach || true; fi
  rm -rf "$work"
}
trap cleanup EXIT

mkdir "$mount_point"
hdiutil convert "$template" -quiet -ov -format UDRW -o "$staging"
hdiutil attach "$staging" -quiet -noautoopen -nobrowse -mountpoint "$mount_point"
mounted=true

if [[ ! -e "$mount_point/$app_name" ]]; then
  echo "The template has no $app_name, so its window layout wouldn't apply to the app" >&2
  exit 1
fi
# ditto would merge into the placeholder instead of replacing it.
rm -rf "${mount_point:?}/$app_name"
ditto "$app" "$mount_point/$app_name"
detach

mkdir -p "$(dirname "$dmg")"
hdiutil convert "$staging" -quiet -ov -format UDZO -imagekey zlib-level=9 -o "$dmg"
# Names the file without its folder, so `shasum -c` works next to the downloaded DMG.
(cd "$(dirname "$dmg")" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
echo "Wrote $dmg and $dmg.sha256"
