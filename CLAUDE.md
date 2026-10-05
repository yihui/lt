# Claude Instructions

## Testing locally with litedown::fuse()

Before calling `litedown::fuse()` to render examples, run
`devtools::load_all(".")` and set `options(lt.local = TRUE)` so that asset URLs
resolve to local `file://` paths (e.g., `file:///path/to/lt/inst/www/lt.js`)
instead of the CDN (which may be stale). Dedup still works because the linked
tags are identical across tables.

## Publish lt to npm

When asked to "publish lt to npm", run `tools/publish-npm.sh`. It copies lt's
assets to the lite.js (`@xiee/utils`) repo, bumps and tags the next version,
pushes, and pins `Config/lt.js` in `DESCRIPTION`. After it runs, review and
commit the `DESCRIPTION` change in lt.

## Test Instructions

### When to run tests

Don't run the test suite after every edit; that wastes time. Run tests only
when you are about to push, or when a change is tricky enough that you are not
confident it is correct. For small, obvious changes, skip the local run and let
CI catch any regression. When you do run, prefer a `--filter` subset over the
full suite.

### What to test

Test observable behavior, not implementation details. Don't write assertions
that merely re-test a dependency (e.g. that `xfun::js()` emits a string
verbatim) or that restate trivial pass-through (e.g. that an option appears in
the serialized spec when set). A test earns its place only if it could
plausibly catch a real regression in this package's own logic.

### How to run

``` bash
CI=true Rscript tests/test-all.R
```

Run a subset of tests by passing a regex filter:

```bash
CI=true Rscript tests/test-all.R --filter=test-render
```

Tests are typically in `tests/testit/test-*.R` (for each `R/foo.R`, there is a
corresponding `tests/testit/test-foo.R`). In certain cases they may be in other
directories, e.g., `tests/test-cran/` (for tests to run on anywhere, including
CRAN) and `tests/test-ci/` (tests to run on CI only because they might fail on
CRAN due to Internet connection or resource limits). The conditioning is done in
top-level `*.R` under `tests/`, e.g.,

``` r
# test everywhere
testit::test_pkg(dir = 'test-cran')

# test on CI only
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

Match the surrounding code for formatting: single quotes, 2-space indent,
compact `if` without braces, many-argument definitions wrapped at 80 chars
(break after the opening `(`), and re-wrap lines you touch. Beyond what the
code already shows:

1.  **Assignment**: use `=`, not `<-`.
2.  **Avoid `\dontrun{}`** unless absolutely necessary; prefer runnable examples
    that can be tested automatically.
3.  **Implicit NULL**: no `else NULL` (a bare `if` already returns `NULL`); use
    `return()`, never `return(NULL)`.
4.  **US spelling** in all docs, comments, and example text (e.g., "color" not
    "colour", "center" not "centre").

### Git workflow

1.  **Never force push** unless explicitly told to.
2.  **Never create a new branch or PR** without confirming with the user first.
3.  **Batch pushes**: Commits are cheap, but every push triggers GHA (slow).
    Commit locally as you go, but push only once everything is ready (all
    related changes, including any npm publish and the resulting DESCRIPTION
    pin). Never push several times in quick succession for one logical unit of
    work.

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
