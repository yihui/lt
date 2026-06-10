d = data.frame(a = 1:3, b = 4:6, c = 7:9)
x = lt(d)

assert("lt_header() sets header", {
  h = lt_header(x, "Title", "Sub")
  (h$header %==% list(title = "Title", subtitle = "Sub"))
  # NULL fields are dropped
  h2 = lt_header(x, "Title")
  (h2$header %==% list(title = "Title"))
})

assert("lt_spanner() with formula", {
  s = lt_spanner(x, Grp ~ b + c)
  (s$spanners %==% list(list(label = "Grp", columns = I(c("b", "c")))))
})

assert("lt_spanner() with no args sets auto_span", {
  s = lt_spanner(x)
  (s$auto_span %==% TRUE)
  s2 = lt_spanner(x, sep = "[_]")
  (s2$auto_span %==% "[_]")
})

assert("lt_group(~ col) sets row_group", {
  d2 = data.frame(g = c("A", "B", "A"), v = 1:3)
  g = lt(d2) |> lt_group(~ g)
  (g$row_group %==% I("g"))
})

assert("lt_group(~ col, sep = TRUE) sets scalar row_group", {
  d2 = data.frame(g = c("A", "B", "A"), v = 1:3)
  g = lt(d2) |> lt_group(~ g, sep = TRUE)
  (g$row_group %==% "g")
})

assert("lt_group() manual groups add ops", {
  g = lt_group(x, "First" = 1:2, "Second" = 3L)
  (g$ops %==% list(
    list(type = "row_group", label = "First", rows = I(1:2)),
    list(type = "row_group", label = "Second", rows = I(3L))
  ))
})

assert("lt_group(sort = FALSE) sets sort", {
  d2 = data.frame(g = c("B", "A"), v = 1:2)
  g = lt(d2) |> lt_group(~ g, sort = FALSE)
  (g$sort %==% FALSE)
})

assert("lt_footnote() builds correct location", {
  f = lt_footnote(x, "note", "column", ~ a)
  (f$footnotes %==% list(list(
    text = "note", location = list(type = "column_labels", columns = I("a"))
  )))

  f2 = lt_footnote(x, "note", "title")
  (f2$footnotes[[1]]$location %==% list(type = "title", group = "title"))

  f3 = lt_footnote(x, "note", "group", "G", match = "starts_with")
  (f3$footnotes[[1]]$location %==% list(
    type = "row_groups", match = "starts_with", value = "G"
  ))
})

assert("lt_note() appends notes", {
  n = lt_note(x, "Source: data") |> lt_note("Another note")
  (n$notes %==% list("Source: data", "Another note"))
})

assert("lt_align() adds align op", {
  a = lt_align(x, ~ a + b, "center")
  (a$ops %==% list(list(type = "align", columns = I(c("a", "b")), align = "center")))
})

assert("lt_format() adds fmt_number op", {
  f = lt_format(x, ~ a, decimals = 2, big_mark = ",")
  (f$ops %==% list(list(
    type = "fmt_number", columns = I("a"), decimals = 2, big_mark = ","
  )))
})

assert("lt_format() supports numeric column indices", {
  f = lt_format(x, 1:2, decimals = 1)
  (f$ops[[1]]$columns %==% I(c("a", "b")))
})

assert("lt_format() percent option", {
  f = lt_format(x, ~ a, percent = TRUE)
  (f$ops[[1]]$percent %==% TRUE)
  f2 = lt_format(x, ~ a, percent = "%")
  (f2$ops[[1]]$percent %==% "%")
})

assert("lt_label() adds label op", {
  l = lt_label(x, a = "Alpha", b = "Beta")
  (l$ops %==% list(list(type = "label", labels = list(a = "Alpha", b = "Beta"))))
})

assert("lt_sub() adds sub op", {
  s = lt_sub(x, ~ a, missing = "—", zero = "-")
  (s$ops %==% list(list(
    type = "sub", columns = I("a"), missing = "—", zero = "-"
  )))
})

assert("lt_indent() adds indent op", {
  i = lt_indent(x, rows = 2:3, level = 2)
  (i$ops %==% list(list(type = "indent", rows = I(2:3), level = 2L)))
})

assert("lt_merge() requires 2+ columns", {
  err = tryCatch(lt_merge(x, ~ a), error = conditionMessage)
  (matches(err, ".*at least 2.*") %==% "")
})

assert("lt_merge() adds merge op", {
  m = lt_merge(x, ~ a + b, pattern = "{1} ({2})")
  (m$ops %==% list(list(
    type = "merge", columns = I(c("a", "b")), pattern = "{1} ({2})", hide = TRUE
  )))
})

assert("lt_style() builds CSS from arguments", {
  s = lt_style(x, "a", bold = TRUE, italic = TRUE, color = "red", bg = "#fff")
  css = s$ops[[1]]$css
  (matches(css, ".*font-weight:bold.*font-style:italic.*color:red.*background:#fff.*") %==% "")
})

assert("lt_style() with extra CSS properties", {
  s = lt_style(x, "a", borderLeft = "1px solid")
  (matches(s$ops[[1]]$css, ".*border-left:1px solid.*") %==% "")
})

assert("lt_style() with class and test", {
  s = lt_style(x, "a", test = "v => v > 1", class = "hi")
  (s$ops[[1]]$class %==% "hi")
  (class(s$ops[[1]]$test) %==% class(xfun::js("")))
})

assert("lt_style() returns unchanged if no css or class", {
  s = lt_style(x, "a")
  (length(s$ops) %==% 0L)
})

assert("lt_width() adds width op", {
  w = lt_width(x, a = "100px", b = "50%")
  (w$ops %==% list(list(type = "width", widths = list(a = "100px", b = "50%"))))
})

assert("lt_move() adds move op", {
  m = lt_move(x, ~ c, after = "a")
  (m$ops %==% list(list(type = "move", columns = I("c"), after = "a")))
})

assert("lt_move() with after = NULL moves to start", {
  m = lt_move(x, ~ b, after = NULL)
  (m$ops %==% list(list(type = "move", columns = I("b"))))
})

assert("lt_css() stores inline rules", {
  c1 = lt_css(x, .na = "background: #eee")
  (c1$rules %==% "  .na { background: #eee }")
})

assert("lt_css() with list-style rules", {
  c1 = lt_css(x, .hi = list(color = "red", fontWeight = "bold"))
  (c1$rules %==% "  .hi { color: red; font-weight: bold; }")
})

assert("lt_css() resolves bundled stylesheets", {
  c1 = lt_css(x, "lt.css")
  (length(c1$css) %==% 1L)
  (file.exists(c1$css[1]))
})

assert("lt_css() handles absolute and URL paths", {
  tmp = tempfile(fileext = ".css")
  writeLines("td{}", tmp)
  c1 = lt_css(x, tmp)
  (c1$css %==% tmp)
  unlink(tmp)
  c2 = lt_css(x, "https://example.com/theme.css")
  (c2$css %==% "https://example.com/theme.css")
})

assert("lt_stub() sets row_label and stubhead op", {
  s = lt_stub(x, ~ a)
  (s$row_label %==% "a")
  (length(s$ops) %==% 0L)
  s2 = lt_stub(x, ~ a, label = "ID")
  (s2$row_label %==% "a")
  (s2$ops %==% list(list(type = "stubhead", label = "ID")))
})
