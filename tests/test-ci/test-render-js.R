# Core static rendering: table structure, column hiding, HTML escaping,
# raw-HTML I() fields, and automatic column labels.

assert("lt_hide drops a column (header and cells) from the rendered table", {
  x = lt(data.frame(x = 1:2, y = c("a", "b"), z = 3:4)) |> lt_hide("y")
  html = as.character(lt_static(x, method = 'node', css = FALSE, fragment = TRUE))
  # kept columns render; hidden one leaves no header or cells
  (has_match(html, ">x</th>"))
  (has_match(html, ">z</th>"))
  (has_match(html, !">y</th>"))
  (has_match(html, !">a</td>"))
})

assert("table is wrapped in a div for horizontal scroll", {
  html = build(list(data = list(x = 1:2)))
  (has_match(html, '<div class="lt-wrap"><table.*</table></div>'))
})

assert("lt_wrap attributes land on the wrapper, class appended, values escaped", {
  html = build(list(data = list(x = 1), wrap = list(
    class = "foo", style = 'width:1px', id = 'a"b'
  )))
  (has_match(html, '<div class="lt-wrap foo" style="width:1px" id="a&quot;b"><table'))
})

assert("cells are HTML-escaped by default", {
  html = build(list(data = list(x = c("<b>a</b>", "c & d"))))
  (has_match(html, ">&lt;b&gt;a&lt;/b&gt;</td>.*>c &amp; d</td>"))
})

assert("html_cols = TRUE emits all data cells as raw HTML", {
  html = build(list(data = list(x = "<b>a</b>"), html_cols = TRUE))
  (has_match(html, "<td[^>]*><b>a</b></td>"))
})

assert("html_cols marks only the listed columns raw", {
  html = build(list(
    data = list(a = "<i>x</i>", b = "<i>y</i>"),
    html_cols = list("a")
  ))
  # column a is raw, column b is escaped
  (has_match(html, "<td[^>]*><i>x</i></td>"))
  (has_match(html, ">&lt;i&gt;y&lt;/i&gt;</td>"))
})

# Text field (title, label, footnote, ...) wrapped in I() in R arrives as
# one-element array, emitted verbatim; plain string is escaped.
assert("I()-wrapped title is raw HTML; a plain title is escaped", {
  html = build(list(data = list(x = 1), header = list(title = I("<b>T</b>"))))
  (has_match(html, 'class="lt-title"><b>T</b>'))
  html = build(list(data = list(x = 1), header = list(title = "<b>T</b>")))
  (has_match(html, 'class="lt-title">&lt;b&gt;T&lt;/b&gt;'))
})

assert("I()-wrapped column label is raw HTML", {
  html = build(list(
    data = list(a = 1, b = 2),
    ops = list(list(type = "label", labels = list(a = I("<b>A</b>"), b = "<b>B</b>")))
  ))
  # a's label raw, b's escaped
  (has_match(html, "<th[^>]*><b>A</b></th>"))
  (has_match(html, "&lt;b&gt;B&lt;/b&gt;</th>"))
})

assert("relabeled column header shows original name as title", {
  html = build(list(
    data = list(a_b = 1, c = 2),
    ops = list(list(type = "label", labels = list(a_b = "Alpha")))
  ))
  (has_match(html, '<th scope="col" class="al-r" title="a_b">Alpha</th>'))
  (has_match(html, !I('title="c"')))
})

assert("html_cols makes separator-row group labels raw HTML", {
  html = build(list(
    data = list(g = c("<b>A</b>", "<b>A</b>", "<b>B</b>"), v = 1:3),
    row_group = "g",
    html_cols = list("g")
  ))
  (has_match(html, 'class="lt-row-group"><th[^>]*><b>A</b></th>'))
  (has_match(html, "<b>B</b></th>"))
})

assert("I()-wrapped spanner, footnote, and note are raw HTML", {
  html = build(list(
    data = list(a = 1, b = 2),
    spanners = list(list(label = I("<b>S</b>"), columns = list("a", "b"))),
    footnotes = list(list(
      text = I("<i>fn</i>"),
      location = list(type = "column_labels", columns = list("a"))
    )),
    notes = list(I("<u>note</u>"))
  ))
  (has_match(html, 'class="lt-spanner"><b>S</b>'))
  (has_match(html, "<i>fn</i></td>"))
  (has_match(html, "<u>note</u></td>"))
})

assert("auto_label replaces separators with spaces in column headers", {
  html = build(list(data = list(Sepal.Length = c(5.1), Petal_Width = c(0.2))))
  (has_match(html, '>Sepal Length</th>.*>Petal Width</th>'))
})

assert("auto_label = FALSE preserves raw column names", {
  html = build(list(data = list(Sepal.Length = c(5.1), Petal_Width = c(0.2)), auto_label = FALSE))
  (has_match(html, '>Sepal\\.Length</th>.*>Petal_Width</th>'))
})

assert("lt_css() rules are scoped inside the table wrapper", {
  html = build(list(data = list(x = 1), rules = ".hi { color: red }"))
  (has_match(html, I("</table><style>@scope{:scope{.hi { color: red }}}</style></div>")))
  (has_match(html, !I("<style>.lt-table")))
})

assert("lt_color() interpolates the palette; NA is unfilled and values are clamped", {
  html = build(list(
    data = list(x = c(0, 5, 10, NA, 20)),
    ops = list(list(type = "color", columns = list("x"),
      palette = list("#000000", "#ffffff"), domain = list(0, 10)))
  ))
  (has_match(html, I('style="background:rgb(0,0,0);color:#fff">0')))
  (has_match(html, I('style="background:rgb(128,128,128);color:#000">5')))
  (has_match(html, I('style="background:rgb(255,255,255);color:#000">20')))
  (has_match(html, !I('background:rgb(255,255,255);color:#000">—')))
  # without a domain, the column's own range is used
  html = build(list(
    data = list(x = c(1, 3)),
    ops = list(list(type = "color", columns = list("x"),
      palette = list("#000000", "#ffffff")))
  ))
  (has_match(html, I('background:rgb(255,255,255);color:#000">3')))
  # contrast = FALSE leaves the text color alone
  html = build(list(
    data = list(x = c(1, 3)),
    ops = list(list(type = "color", columns = list("x"),
      palette = list("#000000", "#ffffff"), contrast = FALSE))
  ))
  (has_match(html, I('style="background:rgb(0,0,0)">1')))
  (has_match(html, !I("color:#")))
})

assert("lt_summary() renders group summaries in place and pins the grand summary in the footer", {
  d = data.frame(g = c("A", "A", "B"), item = c("x", "y", "z"), n = c(1, 2, 3))
  x = lt(d) |> lt_summary(function(x) list(n = sum(x$n)), by = ~ g, label = "Sub", grand = "All") |>
    lt_group(~ g, sep = TRUE)
  html = build(x)
  (count_str(html, 'class="lt-summary"') %==% 3L)
  # a group summary closes its group (the next group header follows it)
  (has_match(html, I('>Sub</td><td class="al-r">3</td></tr><tr class="lt-row-group">')))
  # the grand row is pinned in <tfoot>, after the body
  (has_match(html, '</tbody><tfoot class="lt-footer"><tr class="lt-summary"><td[^>]*>All</td><td[^>]*>6</td>'))
})
