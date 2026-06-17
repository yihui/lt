# LT

Lightweight tables for R, inspired by [gt](https://gt.rstudio.com).

**lt** provides a small grammar of tables that covers the structure most reports
need — titles, column spanners, row groups, footnotes, and number formatting —
without the heavy dependency stack. It targets HTML only (no LaTeX or RTF),
which keeps the implementation minimal: the entire runtime is a single
vanilla-JS file ([under 10 KB
minified](https://cdn.jsdelivr.net/npm/@xiee/utils/js/lt.min.js)).

## Example

``` r
library(lt)

d = data.frame(
  Group = c("Treatment", "Treatment", "Control", "Control"),
  Endpoint = c("Primary", "Secondary", "Primary", "Secondary"),
  Estimate = c(0.6123, 0.7891, 0.4567, 0.5432),
  CI_Lower = c(0.4012, 0.5678, 0.2345, 0.3210),
  CI_Upper = c(0.8234, 1.0104, 0.6789, 0.7654),
  P_Value = c(0.0012, 0.0456, 0.1234, 0.2345)
)
lt(d) |>
  lt_group(~ Group) |>
  lt_header("Study Results", "Primary and secondary endpoints") |>
  lt_spanner(`95% CI` ~ CI_Lower + CI_Upper) |>
  lt_format(~ Estimate + CI_Lower + CI_Upper, decimals = 3) |>
  lt_format(~ P_Value, decimals = 4) |>
  lt_footnote("Two-sided p-value from log-rank test.", "column", ~ P_Value)
```

More examples at <https://pkg.yihui.org/lt/examples.html>.

## Installation

``` r
install.packages("lt", repos = "https://yihui.r-universe.dev")
```

## Acknowledgements

This package was written with the help of Claude Code. **lt** is directly
inspired by **gt** by Rich Iannone and the RStudio/Posit team. The grammar of
tables that **gt** pioneered — layering titles, spanners, footnotes, and
formatters onto a data frame — is a great idea; **lt** aims to provide a minimal
re-implementation for contexts where a lighter footprint is preferred.
