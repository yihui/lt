# Missing-value substitution: lt_sub() and the spec-level missing text.

assert("sub replaces NA", {
  html = build(list(
    data = list(x = c(1, NA)),
    ops = list(list(type = "sub", missing = "—"))
  ))
  (has_match(html, ">—</td>"))
})

assert("spec$missing fills NA cells, leaving empty strings blank", {
  # NA -> the given missing text; an empty string in the data stays empty.
  html = build(list(
    data = list(x = c("a", NA), y = c("", "b")),
    missing = "n/a"
  ))
  (has_match(html, ">a</td>.*>n/a</td>"))
  # the empty-string cell is untouched
  (has_match(html, "></td>"))
})

assert("missing defaults to an em dash; empty string keeps NA cells blank", {
  # no `missing` in the spec: the runtime fills NA cells with an em dash
  html = build(list(data = list(x = c("a", NA))))
  (has_match(html, ">a</td>.*>—</td>"))
  # missing = "" overrides the default and leaves NA cells blank
  html = build(list(data = list(x = c("a", NA)), missing = ""))
  (has_match(html, !">—<"))
})

assert("per-column lt_sub(missing=) overrides the global missing text", {
  html = build(list(
    data = list(x = c(1, NA), y = c(2, NA)),
    missing = "—",
    ops = list(list(type = "sub", columns = list("x"), missing = "n/a"))
  ))
  # column x uses the sub override, column y falls back to the global default
  (has_match(html, ">n/a</td>.*>—</td>"))
})
