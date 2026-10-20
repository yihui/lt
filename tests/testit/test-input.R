d = data.frame(a = c(1, 2), b = c('x', 'y'))

assert('input_spec() marks editable columns, default all', {
  (has_match(input_spec(d), '"input": \\["a", "b"\\]'))
  (has_match(input_spec(d, 'b'), '"input": \\["b"\\]'))
  (has_match(input_spec(d, ~ a), '"input": \\["a"\\]'))
})

assert('input_spec() rejects interactive tables', {
  (has_error(input_spec(lt(d) |> lt_interactive())))
})

assert('input_data() rebuilds a typed data frame, with NA for null cells', {
  x = input_data(list(a = list(1, NULL), b = list('x', 'y')))
  (x %==% data.frame(a = c(1, NA), b = c('x', 'y')))
})

assert('lt_dependency(input = TRUE) adds the editing script', {
  js = function(...) lt_dependency(...)$script
  ('lt-input.js' %in% js(input = TRUE))
  (!'lt-input.js' %in% js())
})

assert('dependencies with different modules do not share a name (htmltools dedups by name)', {
  (lt_dependency(shiny = TRUE)$name != lt_dependency(input = TRUE)$name)
})
