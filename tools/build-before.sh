#!/bin/sh
#
# Build hook for xfun::pkg_build() / xfun::submit_cran(): download the MINIFIED
# JS/CSS into inst/www so the built tarball ships minified assets instead of the
# full sources (the rendered HTML inlines inst/www/*.js and *.css verbatim, so
# minified = smaller output for every table). The matching build-after.sh
# restores the full sources after the build.
#
# The pinned Config/lt.js version is what the CDN serves, so the minified bytes
# match exactly.

set -eu
cd "$(dirname "$0")/.."   # package root (hooks run with cwd = package dir)

VERSION=$(perl -ne 'print $1 if /^Config\/lt\.js:\s*(\S+)/' DESCRIPTION)
[ -n "$VERSION" ] || { echo "Config/lt.js not found in DESCRIPTION" >&2; exit 1; }

# Refuse to run with dirty assets: build-after.sh restores via `git checkout`
# and would otherwise clobber uncommitted work.
if ! git diff --quiet -- inst/www; then
  echo "inst/www has uncommitted changes; commit or stash them first." >&2
  exit 1
fi

base="https://cdn.jsdelivr.net/npm/@xiee/utils@$VERSION"
echo "Fetching minified assets for @xiee/utils@$VERSION"

# Overwrite each asset with its minified twin (same filename, so no R code
# changes). lt-binding.js is not published to the CDN, so leave it as-is.
for path in inst/www/*.js inst/www/*.css; do
  name=$(basename "$path")
  [ "$name" = "lt-binding.js" ] && continue
  case "$name" in
    *.js)  sub=js ;;
    *.css) sub=css ;;
  esac
  min=${name%.*}.min.${name##*.}
  echo "  $name <- $sub/$min"
  curl -fsSL "$base/$sub/$min" -o "$path"
done
