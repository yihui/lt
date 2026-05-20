# lt

Lightweight tables for R, inspired by [gt](https://gt.rstudio.com).

`lt` provides a small grammar of tables that covers the structure most
reports need — titles, column spanners, row groups, footnotes, and number
formatting — without the heavy dependency stack. It targets HTML only (no
LaTeX or RTF), which keeps the implementation minimal: the entire runtime
is a single vanilla-JS file under 5 KB.

## Grammar

A table is built in two steps:

1. **Declare** the table with `lt(data)`, optionally naming a column for
   row groups and a column for row labels (the "stub").
2. **Layer on** structure with piped verbs:

| Verb | Purpose |
|------|---------|
| `lt_header()` | Title and subtitle |
| `lt_spanner()` | Label spanning multiple column headers |
| `lt_group()` | Manual row grouping |
| `lt_footnote()` | Anchored footnotes (title, column, spanner, group, body) |
| `lt_note()` | Unanchored footer note |
| `lt_align()` | Override column alignment |
| `lt_format()` | Number formatting (decimals, big mark) |

The result prints to the RStudio Viewer / browser and can be embedded in
R Markdown, Quarto (via litedown or knitr), and Shiny.

## Examples

### Basic table

```r
library(lt)

lt(head(mtcars[, 1:4]))
```

### Title, spanner, and formatting

```r
lt(head(mtcars[, 1:4])) |>
  lt_header("Motor Trend Cars", "First 6 rows") |>
  lt_spanner("Engine", c("cyl", "disp")) |>
  lt_format(c("mpg", "disp"), decimals = 1)
```

### Row groups and footnotes

```r
lt(PlantGrowth, row_group = "group") |>
  lt_header("Plant Growth Experiment") |>
  lt_footnote("Dried weight in grams", "column", "weight") |>
  lt_note("Source: Dobson (1983)")
```

### Clinical-trial example (gsDesign2)

```r
library(gsDesign2)

fixed_design_ahr(
  alpha = 0.025, power = 0.9,
  enroll_rate = define_enroll_rate(duration = 18, rate = 20),
  fail_rate = define_fail_rate(
    duration = c(4, 100), fail_rate = log(2) / 12,
    dropout_rate = .001, hr = c(1, .6)
  ),
  study_duration = 36
) |>
  summary() |>
  lt() |>
  lt_header("Fixed Design under AHR Method") |>
  lt_footnote("Power based on average hazard ratio method.", "title") |>
  lt_format(c("N", "Events", "AHR", "Bound", "Power"), decimals = 4)
```

## Installation

```r
remotes::install_github("yihui/lt")
```

## Acknowledgements

`lt` is directly inspired by [gt](https://gt.rstudio.com) by Rich Iannone
and the RStudio/Posit team. The grammar of tables that gt pioneered —
layering titles, spanners, footnotes, and formatters onto a data frame — is
a great idea; `lt` aims to provide a minimal re-implementation for contexts
where a lighter footprint is preferred.

## Status

Pre-alpha. The first goal is feature parity with what `gsDesign2::as_gt()`
needs (HTML output only). Beyond that, we look to the
[R Tables for Regulatory Submissions](https://rconsortium.github.io/rtrs-wg/)
work to cover what clinical-trial TLFs typically need.
