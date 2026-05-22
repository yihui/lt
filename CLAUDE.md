# Claude Instructions

## Testing locally with litedown::fuse()

Before calling `litedown::fuse()` to render examples, run `devtools::load_all(".")` and set
`options(lt.local = TRUE)` so that asset URLs resolve to local `file://`
paths (e.g., `file:///path/to/lt/inst/www/lt.js`) instead of the CDN
(which may be stale). Dedup still works because the linked tags are
identical across tables.

## Publish lt to npm

When asked to "publish lt to npm":

1. If `../lite.js/` doesn't exist, clone it from https://github.com/yihui/lite.js.
2. Copy `lt.js` and `lt.css` from this lt R package to `../lite.js/`.
3. In `../lite.js/`: commit `lt.js` and `lt.css`, bump the package version, create a git tag, and push.
4. In this lt package: update the lt.js version reference to match the newly published version.
