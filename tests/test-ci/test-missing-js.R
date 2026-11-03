# Missing-value substitution: lt_sub() and the spec-level missing text.

assert("sub replaces NA", {
  html = build(list(
    data = list(x = c(1, NA)),
    ops = list(list(type = "sub", missing = "—"))
  ))
  (has_match(html, ">—</td>"))
})

assert("spec$missing fills NA cells, leaving empty strings blank", {
  # NA -> given missing text; empty string in data stays empty.
  html = build(list(
    data = list(x = c("a", NA), y = c("", "b")),
    missing = "n/a"
  ))
  (has_match(html, ">a</td>.*>n/a</td>"))
  # empty-string cell untouched
  (has_match(html, "></td>"))
})

assert("missing defaults to an em dash; empty string keeps NA cells blank", {
  # no `missing` in spec: runtime fills NA cells with em dash
  html = build(list(data = list(x = c("a", NA))))
  (has_match(html, ">a</td>.*>—</td>"))
  # missing = "" overrides default, leaves NA cells blank
  html = build(list(data = list(x = c("a", NA)), missing = ""))
  (has_match(html, !">—<"))
})

assert("per-column lt_sub(missing=) overrides the global missing text", {
  html = build(list(
    data = list(x = c(1, NA), y = c(2, NA)),
    missing = "—",
    ops = list(list(type = "sub", columns = list("x"), missing = "n/a"))
  ))
  # column x uses sub override, y falls back to global default
  (has_match(html, ">n/a</td>.*>—</td>"))
})
