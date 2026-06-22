d = data.frame(x = 1:3, y = c("a", "b", "c"))

assert("lt() returns object with data and ops", {
  x = lt(d)
  (x$data %==% d)
  (x$ops %==% list())
})

assert("lt(auto_format = FALSE) sets auto_format", {
  x = lt(d, auto_format = FALSE)
  (x$auto_format %==% FALSE)
  # default does not include auto_format
  (is.null(lt(d)$auto_format))
})

assert("lt(auto_label = FALSE) sets auto_label", {
  x = lt(d, auto_label = FALSE)
  (x$auto_label %==% FALSE)
  (is.null(lt(d)$auto_label))
})

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

assert("camel2dash() converts camelCase to dash-case", {
  (camel2dash(c("borderLeft", "backgroundColor", "color")) %==%
    c("border-left", "background-color", "color"))
})

assert("add_op() appends an operation", {
  x = lt(d)
  x = add_op(x, "test", foo = "bar")
  (x$ops %==% list(list(type = "test", foo = "bar")))
})

assert("add_op() drops NULL values", {
  x = lt(d)
  x = add_op(x, "test", foo = "bar", baz = NULL)
  (names(x$ops[[1]]) %==% c("type", "foo"))
})
