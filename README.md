# LT

<!-- badges: start -->

[![R-CMD-check](https://github.com/yihui/lt/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/yihui/lt/actions/workflows/R-CMD-check.yaml)
[![CRAN release](https://www.r-pkg.org/badges/version/lt)](https://cran.r-project.org/package=lt)
[![lt on r-universe](https://yihui.r-universe.dev/badges/lt)](https://yihui.r-universe.dev/lt)
[![lt.min.js size](https://img.badgesize.io/https://cdn.jsdelivr.net/npm/@xiee/utils/js/lt.min.js?compression=gzip&label=lt.min.js%20gzip)](https://cdn.jsdelivr.net/npm/@xiee/utils/js/lt.min.js)
[![Build site](https://github.com/yihui/lt/actions/workflows/litedown-site.yml/badge.svg)](https://github.com/yihui/lt/actions/workflows/litedown-site.yml)

<!-- badges: end -->

Lightweight tables for R, inspired by [**gt**](https://gt.rstudio.com) and
[**DT**](https://github.com/rstudio/DT).

**lt** provides a small grammar of tables that covers the structure most reports
need — titles, column spanners, row groups, footnotes, and number formatting —
without the heavy dependency stack. Tables render as HTML, and `lt_export()`
also writes PDF, PNG, CSV, and RTF. The entire runtime is a single, tiny
vanilla-JS file (see the size badge above).

Tables can also hold inline plots (`lt_errorbar()`, `lt_sparkline()`,
`lt_dotplot()`) and be made interactive — sorting, searching, per-column
filtering, pagination, resizable columns, column hiding, expandable row detail,
and CSV/RTF download — with `lt_interactive()`.

Both inline plots and interactivity live in separate extensions on top of the
core runtime (`lt-plot.js` and `lt-interactive.js`), each loaded only for the
tables that use it. A plain static table pulls in neither, so it stays as light
as ever.

[![An lt cheat table for static tables.](https://pkg.yihui.org/lt/examples/01-lt-static.png)](https://pkg.yihui.org/lt/examples/01-lt.html#sec:cheat-static)
[![An lt cheat table for interactive tables.](https://pkg.yihui.org/lt/examples/01-lt-interactive.png)](https://pkg.yihui.org/lt/examples/01-lt.html#sec:cheat-interactive)
[![An lt cheat table for inline plots.](https://pkg.yihui.org/lt/examples/01-lt-plots.png)](https://pkg.yihui.org/lt/examples/01-lt.html#sec:cheat-plots)

## Installation

``` r
# CRAN version
install.packages("lt")

# development version
install.packages("lt", repos = "https://yihui.r-universe.dev")
```

You may also play with the package at <https://pkg.yihui.org/lt/playground/>
without installing it.

## Functions

`lt()` creates a table object from a data frame. The `lt_*()` functions build
on it via the pipe. See the manual at <https://pkg.yihui.org/lt/manual.html>
for all functions, grouped by task. The "cheat tables" at
<https://pkg.yihui.org/lt/examples/01-lt.html#sec:cheatsheet> give a visual
overview, and the book at <https://pkg.yihui.org/lt/book/> is a guided tour.

## Examples

The R code below builds a table spec. Under the hood **lt** serializes it to a
compact JSON object and ships it to the browser, where a tiny vanilla-JS runtime
renders the `<table>`.

``` r
library(lt)

d = data.frame(
  Group = c("Treatment", "Treatment", "Control", "Control"),
  Endpoint = c("Primary", "Secondary", "Primary", "Secondary"),
  Estimate = c(0.6123, 0.7891, 0.4567, 0.5432),
  CI_Lower = c(0.4012, 0.5678, 0.2345, 0.3210),
  CI_Upper = c(0.8234, 1.0104, 0.6789, 0.7654),
  P_Value = c(0.0012, NA, 0.1234, NA)
)
lt(d) |>
  lt_group(~ Group) |>
  lt_header("Study Results", "Primary and secondary endpoints") |>
  lt_spanner(`95% CI` ~ CI_Lower + CI_Upper) |>
  lt_format(~ Estimate + CI_Lower + CI_Upper, decimals = 3) |>
  lt_sub(~ P_Value, missing = "n/a") |>
  lt_footnote("Two-sided p-value from log-rank test.", "column", ~ P_Value)
```

The same table can be built directly in JavaScript. Load `lt.js` once on the
page, then call `LT.build()` from an inline `<script>` with the JSON spec:

``` html
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@xiee/utils/css/lt.min.css">
<script src="https://cdn.jsdelivr.net/npm/@xiee/utils/js/lt.min.js"></script>
```

``` js
<script>
LT.build({
  "data": {
    "Group":    ["Treatment", "Treatment", "Control", "Control"],
    "Endpoint": ["Primary", "Secondary", "Primary", "Secondary"],
    "Estimate": [0.6123, 0.7891, 0.4567, 0.5432],
    "CI_Lower": [0.4012, 0.5678, 0.2345, 0.3210],
    "CI_Upper": [0.8234, 1.0104, 0.6789, 0.7654],
    "P_Value":  [0.0012, null, 0.1234, null]
  },
  "ops": [
    { "type": "fmt_number", "columns": ["Estimate", "CI_Lower", "CI_Upper"], "decimals": 3 },
    { "type": "sub", "columns": ["P_Value"], "missing": "n/a" }
  ],
  "row_group": ["Group"],
  "header": { "title": "Study Results", "subtitle": "Primary and secondary endpoints" },
  "spanners": [{ "label": "95% CI", "columns": ["CI_Lower", "CI_Upper"] }],
  "footnotes": [{
    "text": "Two-sided p-value from log-rank test.",
    "location": { "type": "column_labels", "columns": ["P_Value"] }
  }]
});
</script>
```

`LT.build()` renders the table in place of the calling `<script>` tag. One
`lt.js` inclusion handles any number of tables on the page.

You can find more examples at <https://pkg.yihui.org/lt/examples.html>. If you
are coming from **gt**, see the migration guide at
<https://pkg.yihui.org/lt/book/#chp:gt> for a function-by-function mapping and
notes on where **lt** differs.

## Acknowledgements

This package was written with the help of Claude Code. **lt** is directly
inspired by **gt** by Rich Iannone and the RStudio/Posit team. The grammar of
tables that **gt** pioneered — layering titles, spanners, footnotes, and
formatters onto a data frame — is a great idea; **lt** aims to provide a minimal
re-implementation for contexts where a lighter footprint is preferred. Its
interactive features (sorting, searching, paging) were inspired by **DT**, which I
developed with collaborators.
