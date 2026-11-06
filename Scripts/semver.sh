#!/usr/bin/env bash
# Prints the tag of the next release, from the latest release tag in the current repository.
#
# Usage: Scripts/semver.sh patch|minor|major
#
# Only plain vX.Y and vX.Y.Z tags count as releases; others (for example a prerelease) are ignored.
# The first release is v1.0.0 whatever the bump, because there is nothing to bump.
# The tag goes to stdout and an explanation to stderr.
set -euo pipefail

bump=${1:-}
case "$bump" in
  major | minor | patch) ;;
  *)
    echo "Usage: $0 patch|minor|major" >&2
    exit 2
    ;;
esac

pattern='^v([0-9]+)\.([0-9]+)(\.([0-9]+))?$'
latest=$(git tag --list 'v*' | grep -E "$pattern" | sort -V | tail -1 || true)

if [[ -z "$latest" ]]; then
  tag=v1.0.0
  echo "No release yet, so the first release is $tag" >&2
else
  [[ "$latest" =~ $pattern ]]
  major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[4]:-0}
  case "$bump" in
    major) major=$((major + 1)) minor=0 patch=0 ;;
    minor) minor=$((minor + 1)) patch=0 ;;
    patch) patch=$((patch + 1)) ;;
  esac
  tag="v$major.$minor.$patch"
  echo "Latest release: $latest, $bump bump gives $tag" >&2
fi

if git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
  echo "Tag $tag already exists" >&2
  exit 1
fi

echo "$tag"
