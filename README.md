# LT

<!-- badges: start -->

[![R-CMD-check](https://github.com/yihui/lt/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/yihui/lt/actions/workflows/R-CMD-check.yaml)
[![CRAN release](https://www.r-pkg.org/badges/version/lt)](https://cran.r-project.org/package=lt)
[![lt on r-universe](https://yihui.r-universe.dev/badges/lt)](https://yihui.r-universe.dev/lt)

<!-- badges: end -->

Lightweight tables for R, inspired by [gt](https://gt.rstudio.com).

**lt** provides a small grammar of tables that covers the structure most reports
need — titles, column spanners, row groups, footnotes, and number formatting —
without the heavy dependency stack. It targets HTML only (no LaTeX or RTF),
which keeps the implementation minimal: the entire runtime is a single
vanilla-JS file ([about 10 KB
minified](https://cdn.jsdelivr.net/npm/@xiee/utils/js/lt.min.js)).

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
on it via the pipe. See <https://pkg.yihui.org/lt/examples/01-lt#sec:cheatsheet>
for a "cheat table" as an overview of these functions.

**Structure**

- `lt_header()` — title and optional subtitle above the table.
- `lt_spanner()` — column-spanner label spanning a group of columns; or
  auto-infer spanners from column name prefixes.
- `lt_group()` — partition rows into labeled groups (rowspan or full-width
  separator style), either by column values or manual row indices.

**Content & labels**

- `lt_label()` — override column header labels.
- `lt_footnote()` — attach a numbered footnote to any region (title, subtitle,
  column, spanner, group, or body cells).
- `lt_note()` — append a plain unnumbered note below the table.

**Formatting**

- `lt_format()` — numeric formatting: decimal places, thousand separators,
  prefix/suffix, percentage, scientific notation, etc.
- `lt_date()` — date/datetime formatting using the browser locale.
- `lt_sub()` — substitute specific values (e.g., replace `0` with `"—"` or
  `NA` with `"n/a"`).
- `lt_merge()` — merge several columns into one using a sprintf-style pattern.
- `lt_indent()` — indent selected rows (useful for hierarchical row labels).

**Appearance**

- `lt_align()` — set column alignment (left / center / right).
- `lt_width()` — set column widths.
- `lt_style()` — apply CSS classes or inline styles to cells, conditionally or
  unconditionally.
- `lt_css()` — attach an external CSS file or URL to the table.

**Column order**

- `lt_move()` — reorder columns.

**Export**

- `lt_export()` — save a table to a file: `.html` (optionally baking a static
  `<table>` that needs no JavaScript to view), `.pdf`, or `.png` (rendered via a
  headless Chromium browser).

**Shiny**

- `lt_output()` / `render_lt()` — Shiny UI and server bindings.

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
  lt_sub(~ P_Value, missing = "—") |>
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
    { "type": "sub", "columns": ["P_Value"], "missing": "—" }
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

You can find more examples at <https://pkg.yihui.org/lt/examples.html>.

## Acknowledgements

This package was written with the help of Claude Code. **lt** is directly
inspired by **gt** by Rich Iannone and the RStudio/Posit team. The grammar of
tables that **gt** pioneered — layering titles, spanners, footnotes, and
formatters onto a data frame — is a great idea; **lt** aims to provide a minimal
re-implementation for contexts where a lighter footprint is preferred.
