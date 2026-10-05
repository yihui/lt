#!/usr/bin/env bash
#
# Publish lt's JS/CSS assets to npm via the lite.js (@xiee/utils) repo.
#
# Steps (mirrors the "Publish lt to npm" section of CLAUDE.md):
#   1. Ensure ../lite.js exists (clone it if missing); pull --rebase first, so
#      the sync happens on a clean tree before any asset is copied in.
#   2. Copy lt's assets from inst/www into lite.js.
#   3. In lite.js: pick the next unused patch version, bump package.json,
#      commit, tag, and push (branch + the new tag only).
#   4. Update this package's Config/lt.js version in DESCRIPTION to match.
#
# Run from anywhere; paths are resolved relative to this script.
# Never deletes or overrides an existing remote tag: the version is bumped
# until an unused tag is found.

set -euo pipefail

# Files under inst/www that are not published to lite.js.
EXCLUDE=(lt-binding.js)

LT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LITE_DIR=$(cd "$LT_DIR/.." && pwd)/lite.js
WWW="$LT_DIR/inst/www"

# 1. Ensure lite.js is present, then sync with remote on a clean tree (before
#    copying assets in, so the rebase is never blocked by unstaged changes).
if [ ! -d "$LITE_DIR" ]; then
  echo "Cloning lite.js into $LITE_DIR"
  git clone https://github.com/yihui/lite.js "$LITE_DIR"
fi

cd "$LITE_DIR"
git pull --rebase

# 2. Copy every asset under inst/www (except the excluded ones) to lite.js,
#    routing by extension: *.js -> js/, *.css -> css/.
is_excluded() {
  local name=$1 x
  for x in "${EXCLUDE[@]}"; do [ "$name" = "$x" ] && return 0; done
  return 1
}
for path in "$WWW"/*; do
  [ -f "$path" ] || continue
  name=$(basename "$path")
  is_excluded "$name" && continue
  case "$name" in
    *.js)  cp "$path" "$LITE_DIR/js/$name" ;;
    *.css) cp "$path" "$LITE_DIR/css/$name" ;;
  esac
done

# Nothing to publish if the assets are unchanged.
if git diff --quiet; then
  echo "No asset changes; lite.js is already up to date. Nothing to publish."
  exit 0
fi

# 3b. Pick the next version whose tag does not already exist (local or remote).
# Align local tags with the remote first (--force, since a diverged local tag
# would otherwise make `git fetch --tags` fail and abort under `set -e`), so the
# latest-tag scan below sees the authoritative set.
git fetch --tags --force --quiet
tag_exists() { git rev-parse -q --verify "refs/tags/$1" >/dev/null; }

latest=$(git tag | sort -V | tail -1)        # e.g. v1.14.86
base=${latest#v}                             # strip leading v
major=${base%%.*}
rest=${base#*.}
minor=${rest%%.*}
patch=${rest##*.}

while :; do
  patch=$((patch + 1))
  new="$major.$minor.$patch"
  if ! tag_exists "v$new" && ! git ls-remote --tags origin "v$new" | grep -q .; then
    break
  fi
  echo "Tag v$new already exists; bumping further."
done

echo "Publishing @xiee/utils v$new"

# 3c. Bump package.json, commit, tag, push (branch + the single new tag only).
perl -i -pe "s/\"version\": \"[^\"]+\"/\"version\": \"$new\"/ if \$. < 10 && /\"version\"/" package.json

git add -A
git commit -m "Bump to $new (lt assets)"
git tag "v$new"
git push
git push origin "v$new"

# 4. Pin lt to the newly published version.
cd "$LT_DIR"
perl -i -pe "s/^Config\/lt\.js:.*/Config\/lt.js: $new/" DESCRIPTION

echo "Done. Published v$new and pinned DESCRIPTION Config/lt.js to $new."
echo "Review and commit the DESCRIPTION change in lt as appropriate."
