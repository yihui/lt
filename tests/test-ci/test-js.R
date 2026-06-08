js_path = system.file("www", "lt.js", package = "lt")

build = function(spec) {
  json = xfun::tojson(spec)
  paste(system2("node", c("run-js.js", shQuote(js_path)), input = json, stdout = TRUE), collapse = "\n")
}

assert("basic table renders correct cells", {
  html = build(list(data = list(x = 1:2, y = c("a", "b"))))
  (grepl("<table", html))
  (grepl(">x</th>", html))
  (grepl(">1</td>", html))
  (grepl(">b</td>", html))
})

assert("fmt_number formats decimals", {
  html = build(list(
    data = list(x = c(1.1, 2.345)),
    ops = list(list(type = "fmt_number", columns = list("x"), decimals = 2))
  ))
  (grepl("1.10", html))
  (grepl("2.35", html) || grepl("2.34", html))
})

assert("sub replaces NA", {
  html = build(list(
    data = list(x = c(1, NA)),
    ops = list(list(type = "sub", missing = "—"))
  ))
  (grepl("—", html))
})

assert("separator row groups render correctly", {
  html = build(list(
    data = list(g = c("A", "A", "B"), v = 1:3),
    row_group = "g"
  ))
  (grepl("lt-row-group", html))
  (grepl(">A<", html))
  (grepl(">B<", html))
})

assert("rowspan row groups render correctly", {
  html = build(list(
    data = list(g = c("A", "A", "B"), v = 1:3),
    row_group = list("g")
  ))
  (grepl("rowspan", html))
})

assert("column spanner renders colspan", {
  html = build(list(
    data = list(a = 1, b = 2, c = 3),
    spanners = list(list(label = "AB", columns = list("a", "b")))
  ))
  (grepl('colspan="2"', html))
  (grepl(">AB<", html))
})

assert("footnotes render in tfoot", {
  html = build(list(
    data = list(x = 1),
    footnotes = list(list(
      text = "A note",
      location = list(type = "column_labels", columns = list("x"))
    ))
  ))
  (grepl("<tfoot", html))
  (grepl("A note", html))
})

assert("merge with pattern", {
  html = build(list(
    data = list(a = "x", b = "y"),
    ops = list(list(type = "merge", columns = list("a", "b"), pattern = "{1} ({2})", hide = TRUE))
  ))
  (grepl("x (y)", html, fixed = TRUE))
})

assert("style with class and test", {
  html = build(list(
    data = list(x = c(1, 5)),
    ops = list(list(type = "style", columns = list("x"), test = "v => v > 3", class = "hi"))
  ))
  # "hi" applied to cell with 5 but not cell with 1
  (grepl("hi.*>5<", html))
  (!grepl("hi.*>1<", html))
})

assert("sort by groups reorders rows", {
  html = build(list(
    data = list(g = c("B", "A", "B", "A"), v = c(1, 2, 3, 4)),
    row_group = list("g")
  ))
  # After sorting by g, A rows (2,4) come before B rows (1,3)
  a_pos = regexpr(">2<", html)
  b_pos = regexpr(">1<", html)
  (a_pos < b_pos)
})
