#!/usr/bin/env bash
# Cut an iOS release:   scripts/release.sh 1.1.0
#
# Writes the version into Configs/Version.xcconfig — MARKETING_VERSION as given,
# CURRENT_PROJECT_VERSION as the commit count the release commit will have, so the
# build number only ever grows — commits that one file and tags it v<version>.
# Nothing is pushed: `git push origin HEAD --follow-tags` when you mean it.
set -euo pipefail

version="${1:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: scripts/release.sh <major.minor.patch>" >&2
  exit 2
fi

cd "$(git rev-parse --show-toplevel)"
file=Configs/Version.xcconfig

if ! git diff --quiet -- "$file" || ! git diff --cached --quiet -- "$file"; then
  echo "$file has uncommitted changes; commit or drop them first" >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
  echo "tag v$version already exists" >&2
  exit 1
fi
current=$(sed -nE 's/^MARKETING_VERSION = (.*)$/\1/p' "$file")
if [[ "$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -1)" != "$version" || "$current" == "$version" ]]; then
  echo "v$version is not above the current v$current" >&2
  exit 1
fi

other=$(git status --porcelain | grep -vc "^.. $file$" || true)
if [[ "$other" -gt 0 ]]; then
  echo "note: $other other uncommitted path(s) stay out of the release commit" >&2
fi

build=$(( $(git rev-list --count HEAD) + 1 ))
sed -i '' -E \
  -e "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $version/" \
  -e "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $build/" \
  "$file"

git commit -q -m "chore(release): v$version (build $build)" -- "$file"
git tag -a "v$version" -m "Exodus iOS v$version (build $build)"
echo "v$version, build $build — committed and tagged. Push with: git push origin HEAD --follow-tags"
