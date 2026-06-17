# Claude Instructions

## Testing locally with litedown::fuse()

Before calling `litedown::fuse()` to render examples, run
`devtools::load_all(".")` and set `options(lt.local = TRUE)` so that asset URLs
resolve to local `file://` paths (e.g., `file:///path/to/lt/inst/www/lt.js`)
instead of the CDN (which may be stale). Dedup still works because the linked
tags are identical across tables.

## Publish lt to npm

When asked to "publish lt to npm":

1.  If `../lite.js/` doesn't exist, clone it from
    <https://github.com/yihui/lite.js>.
2.  Copy `lt.js` and `lt.css` from this lt R package to `../lite.js/`.
3.  In `../lite.js/`: commit `lt.js` and `lt.css`, bump the package version,
    create a git tag, and push.
4.  In this lt package: update the lt.js version reference to match the newly
    published version.

## Test Instructions

``` bash
export CI=true; for f in tests/*.R; do Rscript "$f"; done
```

Tests are typically in `tests/testit/test-*.R` (for each `R/foo.R`, there is a
corresponding `tests/testit/test-foo.R`). In certain cases they may be in other
directories, e.g., `tests/test-cran/` (for tests to run on anywhere, including
CRAN) and `tests/test-ci/` (tests to run on CI only because they might fail on
CRAN due to Internet connection or resource limits). The conditioning is done in
top-level `*.R` under `tests/`, e.g.,

``` r
# tests/test-cran.R
testit::test_pkg(dir = 'test-cran')

# tests/test-ci.R
if (tolower(Sys.getenv('CI')) == 'true') testit::test_pkg(dir = 'test-ci')
```

Tests consist of assertions of this form:

``` r
library(testit)

assert('expectation message', {
  actual = FUN(args, ...)
  (actual %==% expected)
  # more tests of the above form, e.g.,
  (length(res) %==% 3L)
})
```

-   Use `has_error()` instead of `tryCatch()` for error testing
-   Never use `:::` to access internal functions in tests; testit exposes
    internal functions automatically, so call them directly

## Conventions

### R Code Style

1.  **Assignment**: Use `=` instead of `<-` for assignment
2.  **Strings**: Use single quotes for strings (e.g., `'text'`)
3.  **Indentation**: Use 2 spaces (not 4 spaces or tabs)
4.  **Compact code**: Avoid `{}` for single-expression if statements; prefer
    compact forms when possible
5.  **Examples**: Avoid `\dontrun{}` unless absolutely necessary. Prefer
    runnable examples that can be tested automatically.
6.  **Function definitions**: For functions with many arguments, break the line
    right after the opening `(`, indent arguments by 2 spaces, and try to wrap
    them at 80-char width.
7.  **Re-wrap code**: Always re-wrap the code after making changes to maintain
    consistent formatting and line length.
8.  **Implicit NULL**: Don't write `if (cond) foo else NULL`; the `else NULL` is
    unnecessary since R's `if` without `else` already returns `NULL`. Never
    write `return(NULL)`; use `return()` instead since R functions return `NULL`
    by default when no value is given.
9.  **US spelling**: Use US spelling throughout all documentation, code
    comments, and example text (e.g., "color" not "colour", "center" not
    "centre", "summarize" not "summarise").
10. **DRY (Don't Repeat Yourself)**: Never duplicate code. When the same logic
    appears more than once, factor it into a shared helper function. This
    applies to expressions, patterns, and multi-line blocks alike.

### Git workflow

1.  **Never force push** unless explicitly told to.
2.  **Never create a new branch or PR** without confirming with the user first.

### Check list

Always send a pull request, unless you are told otherwise. For each PR:

1.  **Every change must have tests**: Every code change must come with
    corresponding tests. If you add or fix a function, add assertions in the
    test file that cover the new or fixed behavior. Tests are the first place to
    catch regressions and errors.
2.  **Merge latest main before pushing**: Before pushing to a branch or PR,
    always pull and merge the latest main branch. If there are merge conflicts,
    resolve them before pushing.
3.  **Bump version before pushing**: Bump the patch version number in
    DESCRIPTION and commit (amend current latest commit instead of making a
    separate new commit).
