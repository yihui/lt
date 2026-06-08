# LT

Lightweight tables for R, inspired by [gt](https://gt.rstudio.com).

**lt** provides a small grammar of tables that covers the structure most
reports need — titles, column spanners, row groups, footnotes, and number
formatting — without the heavy dependency stack. It targets HTML only (no
LaTeX or RTF), which keeps the implementation minimal: the entire runtime
is a single vanilla-JS file under 5 KB.

## Example

```r
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

```r
remotes::install_github("yihui/lt")
```

## Acknowledgements

This package was written with the help of Claude Code. While I have verified
that it does not directly copy code from other projects, I do not have a clear
picture of whether it may have indirectly reused open-source code. If you
discover any code in this package that appears to originate from another
project, please [file an issue](https://github.com/yihui/lt/issues) and I will
check whether the license is compatible and the original authors are properly
attributed.

**lt** is directly inspired by **gt** by Rich Iannone and the RStudio/Posit
team. The grammar of tables that **gt** pioneered — layering titles, spanners,
footnotes, and formatters onto a data frame — is a great idea; **lt** aims to
provide a minimal re-implementation for contexts where a lighter footprint is
preferred.

## Status

Alpha. The first goal — feature parity with what `gsDesign2::as_gt()`
needs (HTML output only) — is reached. We now look to the
[R Tables for Regulatory Submissions](https://rconsortium.github.io/rtrs-wg/)
work to cover what clinical-trial TLFs typically need: column merging,
row indentation, value substitution, and column hiding are in place.
