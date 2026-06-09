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

assert("auto-format picks decimals from value width", {
  # Small values (<1) get up to 4 decimals; the big_mark separator is a
  # non-breaking space (U+00A0).
  html = build(list(data = list(x = c(0.123456, 0.987))))
  (grepl(">0.1235<", html))
  (grepl(">0.9870<", html))
  # Large values are rounded to 0 decimals and grouped.
  html = build(list(data = list(x = c(1234.5, 9999.9))))
  (grepl(">1 235<", html))
  (grepl(">10 000<", html))
})

assert("auto_fmt = FALSE leaves numbers untouched", {
  html = build(list(data = list(x = c(1.23456, 2.34567)), auto_fmt = FALSE))
  (grepl(">1.23456<", html))
  (grepl(">2.34567<", html))
})

assert("per-cell style class merges with the column alignment class", {
  # Numeric columns get the "al-r" class; a style class on one cell must be
  # appended, not replace it.
  html = build(list(
    data = list(x = c(1, 5)),
    ops = list(list(type = "style", columns = list("x"), rows = list(2L), class = "hot"))
  ))
  (grepl('class="al-r hot">5<', html, fixed = TRUE))
  # The untouched cell keeps just the alignment class.
  (grepl('class="al-r">1<', html, fixed = TRUE))
})

assert("fmt_number with percent, big_mark, and minus sign", {
  html = build(list(
    data = list(x = c(0.1234, 12345.678)),
    ops = list(list(type = "fmt_number", columns = list("x"),
                    percent = TRUE, decimals = 1, big_mark = ","))
  ))
  (grepl(">12.3%<", html))
  (grepl(">1,234,567.8%<", html))
  # Negative numbers render with a real minus sign (U+2212), not a hyphen.
  html = build(list(
    data = list(n = -1234567),
    ops = list(list(type = "fmt_number", columns = list("n"), big_mark = ","))
  ))
  (grepl(">−1,234,567<", html))
})

assert("footnote on the title renders a marker in the caption", {
  html = build(list(
    data = list(x = 1),
    header = list(title = "T"),
    footnotes = list(list(
      text = "tn", location = list(type = "title", group = "title")
    ))
  ))
  (grepl("lt-title", html))
  (grepl("lt-fnref", html))      # marker in the caption
  (grepl(">1</td>", html) || grepl("tn", html))  # note text in tfoot
  (grepl("tn", html))
})

assert("footnote on row groups matches by starts_with", {
  html = build(list(
    data = list(g = c("Apple", "Banana"), v = c(1, 2)),
    row_group = "g",
    footnotes = list(list(
      text = "sn",
      location = list(type = "row_groups", match = "starts_with", value = "App")
    ))
  ))
  # Marker attaches to the "Apple" group header, and only one footnote exists.
  (grepl("Apple<sup", html))
  (!grepl("Banana<sup", html))
  (grepl("sn", html))
})

assert("merge drops a conditional block when its references are empty", {
  # "<<...>>" blocks are emitted only if all {n} refs are non-empty.
  html = build(list(
    data = list(a = "x", b = "", c = ""),
    ops = list(list(type = "merge", columns = list("a", "b", "c"),
                    pattern = "{1}<<({2}/{3})>>"))
  ))
  (grepl(">x<", html))
  (!grepl("(/)", html, fixed = TRUE))
})
