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

### Design goal: lightweight output

lt's whole pitch is an ultra-lightweight alternative — "no sass, no V8, no
htmltools, just base R and xfun". Every byte of rendered HTML/CSS/JS counts.
Apply this when writing *and when editing* existing code:

- **Compact R and JS alike**: arrow functions, template literals, object
  shorthand, pipes, single-line lambdas. Build big strings with `out.push(...)`
  then `out.join("")`, not a stateful `html += ...` thread.
- **DRY**: extract a repeated pattern into a small helper the moment it recurs.
- **JSON-only payload**: don't emit a server-side `<table>` when the data also
  ships as JSON — send the JSON and let the runtime build the table client-side.
- **Assets once per page**: the CSS + JS runtime are emitted once and shared; a
  per-table `<script>` only calls into the runtime. Route any new render path
  through that same seam.
- **Omit empty spec slots**: never serialize `name: {}` or `name: null` — drop
  the key. Likewise omit empty/NULL list slots in R.
- **No random IDs**: never auto-generate element/table IDs (they churn version
  control diffs); emit `id` only when the user supplies one, and design
  selectors/lookups not to need one.
- **No unnecessary CSS**: only declare properties that change something; don't
  restate browser defaults.
- **No defensive `requireNamespace()`**: in functions whose names already imply a
  Suggests dependency (`lt_output`, `render_lt`, `knit_print.lt_tbl`, …), let R
  raise its normal error rather than guarding.

The sibling package `../gglite` follows the same conventions — consult it for
precedent on minimal rendering.

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
5.  **Reuse xfun**: lt imports xfun — use its helpers (`html_escape`, `tojson`,
    `html_view`, `html_tag`, `record_print`, …) instead of reimplementing. Check
    `ls("package:xfun")` before writing any small text/HTML utility.
6.  **Never hand-edit generated files**: regenerate `*.Rd` and `NAMESPACE` with
    `roxygen2::roxygenise()`, and example `*.html` with `litedown::fuse()`. The
    roxygen comments and `.Rmd` sources are the single source of truth.

### JavaScript Code Style

Match the surrounding code in `inst/www/*.js`: 2-space indent, double quotes,
template literals, arrow functions, compact one-liners where they stay readable.
Beyond that:

1.  **Prefer modern JS**: use current syntax and built-ins freely (arrow
    functions, template literals, optional chaining `?.`, nullish coalescing
    `??`, spread/rest, destructuring, `for...of`, etc.). The runtime targets
    current browsers; no transpilation, so there is no need to write to an old
    baseline.
2.  **Join consecutive `const`s**: collapse a run of adjacent simple `const`
    declarations into one comma-separated statement (`const a = 1, b = 2;`)
    rather than one `const` per line. Exceptions, kept on their own line: a
    `const` whose value is a long or multi-line function, and a `const` that
    carries its own detailed comment — so the comment and structure read clearly.

### Documentation

Comprehensive but user-facing: describe what a function does, when to use it, and
how parameters interact. Omit internal implementation details (JS globals,
internal variable names, data structures, queue mechanics) that may change and
that only a maintainer would care about. Don't frame behavior against a past or
alternative implementation the user never saw — state it directly ("the header
joins all names", not "… rather than just the first").

In `NEWS.md`, never hard-wrap: one line per bullet (and sub-bullet). Readability
comes from the bullet structure, not from wrapping.

### Verify browser fixes

When a change affects rendered HTML/JS, confirm it in a headless browser before
reporting it done — the `tests/test-ci/helper.R` helpers (`lti_eval`,
`lti_rows`) drive one, or use `chromote` / `xfun::browser_dom()`. Check that the
actual DOM is right, not just that the source matches.

`lti_eval(x, expr, js)` wraps `expr` in `(...)` to stamp it on `<body>`, so
`expr` must be a single JavaScript *expression* — multi-statement setup (`var`
declarations, assignments) belongs in the `js` argument, which runs before it.
Putting statements in `expr` makes `(var c = ...)` a syntax error: the load
handler never runs, nothing is stamped, and the test fails only as a probe
timeout (`failed to read the probe value from the browser`), not a clear error.

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
