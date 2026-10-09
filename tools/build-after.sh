#!/bin/sh
#
# Build hook for xfun::pkg_build() / xfun::submit_cran(): restore inst/www after
# the tarball is built, undoing the minification done by build-before.sh. Runs
# even if the build failed. A no-op when nothing changed (e.g. the before hook
# was skipped on CI, or outside a git checkout).

set -eu
cd "$(dirname "$0")/.."   # package root (hooks run with cwd = package dir)

if git rev-parse --git-dir >/dev/null 2>&1 && ! git diff --quiet -- inst/www; then
  git checkout -- inst/www
  echo "Restored inst/www to the committed (full) sources."
fi
