# Core static rendering: table structure, column hiding, HTML escaping,
# raw-HTML I() fields, and automatic column labels.

assert("basic table renders correct cells", {
  html = build(list(data = list(x = 1:2, y = c("a", "b"))))
  (matches(html, ".*<table.*>x</th>.*>1</td>.*>b</td>.*") %==% "")
})

assert("lt_hide drops a column (header and cells) from the rendered table", {
  x = lt(data.frame(x = 1:2, y = c("a", "b"), z = 3:4)) |> lt_hide("y")
  html = as.character(lt_static(x, method = 'node', css = FALSE, fragment = TRUE))
  # the kept columns render, the hidden one leaves no header and no cells
  (grepl(">x</th>", html) %==% TRUE)
  (grepl(">z</th>", html) %==% TRUE)
  (grepl(">y</th>", html) %==% FALSE)
  (grepl(">a</td>", html) %==% FALSE)
})

assert("table is wrapped in a div for horizontal scroll", {
  html = build(list(data = list(x = 1:2)))
  (matches(html, '.*<div class="lt-wrap"><table.*</table></div>.*') %==% "")
})

assert("lt_wrap attributes land on the wrapper, class appended, values escaped", {
  html = build(list(data = list(x = 1), wrap = list(
    class = "foo", style = 'width:1px', id = 'a"b'
  )))
  (matches(html, '.*<div class="lt-wrap foo" style="width:1px" id="a&quot;b"><table.*') %==% "")
})

assert("cells are HTML-escaped by default", {
  html = build(list(data = list(x = c("<b>a</b>", "c & d"))))
  (matches(html, ".*>&lt;b&gt;a&lt;/b&gt;</td>.*>c &amp; d</td>.*") %==% "")
})

assert("html_cols = TRUE emits all data cells as raw HTML", {
  html = build(list(data = list(x = "<b>a</b>"), html_cols = TRUE))
  (matches(html, ".*<td[^>]*><b>a</b></td>.*") %==% "")
})

assert("html_cols marks only the listed columns raw", {
  html = build(list(
    data = list(a = "<i>x</i>", b = "<i>y</i>"),
    html_cols = list("a")
  ))
  # column a is raw, column b is escaped
  (matches(html, ".*<td[^>]*><i>x</i></td>.*") %==% "")
  (matches(html, ".*>&lt;i&gt;y&lt;/i&gt;</td>.*") %==% "")
})

# A text field (title, label, footnote, ...) wrapped in I() on the R side
# arrives as a one-element array and is emitted verbatim; a plain string is
# escaped.
assert("I()-wrapped title is raw HTML; a plain title is escaped", {
  html = build(list(data = list(x = 1), header = list(title = I("<b>T</b>"))))
  (matches(html, '.*class="lt-title"><b>T</b>.*') %==% "")
  html = build(list(data = list(x = 1), header = list(title = "<b>T</b>")))
  (matches(html, '.*class="lt-title">&lt;b&gt;T&lt;/b&gt;.*') %==% "")
})

assert("I()-wrapped column label is raw HTML", {
  html = build(list(
    data = list(a = 1, b = 2),
    ops = list(list(type = "label", labels = list(a = I("<b>A</b>"), b = "<b>B</b>")))
  ))
  # column a's label is raw, b's is escaped
  (matches(html, ".*<th[^>]*><b>A</b></th>.*") %==% "")
  (matches(html, ".*&lt;b&gt;B&lt;/b&gt;</th>.*") %==% "")
})

assert("html_cols makes separator-row group labels raw HTML", {
  html = build(list(
    data = list(g = c("<b>A</b>", "<b>A</b>", "<b>B</b>"), v = 1:3),
    row_group = "g",
    html_cols = list("g")
  ))
  (matches(html, '.*class="lt-row-group"><th[^>]*><b>A</b></th>.*') %==% "")
  (matches(html, ".*<b>B</b></th>.*") %==% "")
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
  (matches(html, '.*class="lt-spanner"><b>S</b>.*') %==% "")
  (matches(html, ".*<i>fn</i></td>.*") %==% "")
  (matches(html, ".*<u>note</u></td>.*") %==% "")
})

assert("auto_label replaces separators with spaces in column headers", {
  html = build(list(data = list(Sepal.Length = c(5.1), Petal_Width = c(0.2))))
  (matches(html, '.*>Sepal Length</th>.*>Petal Width</th>.*') %==% "")
})

assert("auto_label = FALSE preserves raw column names", {
  html = build(list(data = list(Sepal.Length = c(5.1), Petal_Width = c(0.2)), auto_label = FALSE))
  (matches(html, '.*>Sepal\\.Length</th>.*>Petal_Width</th>.*') %==% "")
})
