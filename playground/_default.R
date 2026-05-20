# For more info, see https://pkg.yihui.org/lt/
library(lt)
lt(head(mtcars[, 1:6])) |>
  lt_header(title = "Motor Trend Cars", subtitle = "First six observations") |>
  lt_format(c("mpg", "disp", "drat", "wt"), decimals = 1)
