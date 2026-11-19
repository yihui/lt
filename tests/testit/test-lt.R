d = data.frame(x = 1:3, y = c("a", "b", "c"))

assert("lt() detects grouped_df", {
  gd = structure(d, class = c("grouped_df", "data.frame"),
    groups = data.frame(y = c("a", "b"), .rows = I(list(1L, 2:3))))
  x = lt(gd)
  (x$row_group %==% I("y"))
})

assert("f_cols() extracts variable names from formula", {
  (f_cols(~ a + b) %==% c("a", "b"))
  (f_cols(~ x) %==% "x")
  (f_cols(c("a", "b")) %==% c("a", "b"))
})

assert("f_cols() resolves a predicate formula against column names", {
  d = data.frame(asy_time = 1, sim_time = 1, asy_n = 1, sim_prob = 1)
  # logical predicate selects matching names
  (f_cols(~ endsWith(., "_time"), d) %==% c("asy_time", "sim_time"))
  (f_cols(~ startsWith(., "asy"), d) %==% c("asy_time", "asy_n"))
  (f_cols(~ grepl("_prob$", .), d) %==% "sim_prob")
  # character result is used as-is
  (f_cols(~ grep("_time$", ., value = TRUE), d) %==% c("asy_time", "sim_time"))
  # bare-name formula still works (no `.`)
  (f_cols(~ asy_time + sim_time, d) %==% c("asy_time", "sim_time"))
})

assert("camel2dash() converts camelCase to dash-case", {
  (camel2dash(c("borderLeft", "backgroundColor", "color")) %==%
    c("border-left", "background-color", "color"))
})

assert("name_value_args() canonicalizes the name = value forms", {
  expected = list(a = "A", b = "B")
  # named arguments
  (name_value_args(a = "A", b = "B") %==% expected)
  # single named vector or list
  (name_value_args(c(a = "A", b = "B")) %==% expected)
  (name_value_args(list(a = "A", b = "B")) %==% expected)
  # single list(names, values) of two parallel vectors
  (name_value_args(list(c("a", "b"), c("A", "B"))) %==% expected)
  # single name/value pair is degenerate case
  (name_value_args(list("a", "A")) %==% list(a = "A"))
  # anything else returned unchanged (unnamed scalar, mix, nothing)
  (name_value_args("80%") %==% list("80%"))
  (name_value_args(a = "A", "80%") %==% list(a = "A", "80%"))
  (name_value_args() %==% list())
  # value's class preserved (e.g. I() raw HTML survives split)
  (inherits(name_value_args(list("a", I("<b>A</b>")))$a, "AsIs"))
  (inherits(name_value_args(list(a = I("<b>A</b>")))$a, "AsIs"))
})

assert("add_op() drops NULL values", {
  x = lt(d)
  x = add_op(x, "test", foo = "bar", baz = NULL)
  (names(x$ops[[1]]) %==% c("type", "foo"))
})

assert('lt() lays a monthly time series out by year and month', {
  x = lt(window(AirPassengers, start = c(1949, 3), end = c(1950, 2)))$data
  (names(x) %==% c('Year', month.abb))
  (x$Year %==% c('1949', '1950'))
  # incomplete years are padded with NA
  (is.na(x$Jan[1]) && x$Mar[1] == 132 && is.na(x$Mar[2]))
  (lt(ts(1:8, start = c(2000, 2), frequency = 4))$data$Q2 %==% c(1, 5, NA))
})

assert('lt() gives a Time column for other time series', {
  x = lt(AirPassengers, wide = FALSE)$data
  (names(x) %==% c('Time', 'value'))
  (x$Time[1:2] %==% c('1949 Jan', '1949 Feb'))
  x = lt(EuStockMarkets)$data
  (names(x) %==% c('Time', 'DAX', 'SMI', 'CAC', 'FTSE'))
  (x$Time[1:2] %==% c('1991 #130', '1991 #131'))
  (lt(ts(1:2, start = 2000.5))$data$Time %==% c('2000.5', '2001.5'))
  (names(lt(ts(1:3, start = 2000))$data) %==% c('Time', 'value'))
})

assert('lt() labels quarterly and half-yearly series in the Time column', {
  q = ts(c(10, 11, 9, 12, 13), start = c(2023, 1), frequency = 4)
  (lt(q, wide = FALSE)$data$Time[4:5] %==% c('2023 Q4', '2024 Q1'))
  # a multiple series is never wide
  x = lt(cbind(a = q, b = q * 2))$data
  (names(x) %==% c('Time', 'a', 'b'))
  (x$Time[1] %==% '2023 Q1')
  (lt(ts(1:3, start = c(2000, 1), frequency = 2))$data$Time[3] %==% '2001 #1')
})
