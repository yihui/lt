build = function(spec) {
  x = structure(spec, class = 'lt_tbl')
  as.character(render_html(x, method = 'node', css = FALSE, fragment = TRUE))
}

assert("basic table renders correct cells", {
  html = build(list(data = list(x = 1:2, y = c("a", "b"))))
  (matches(html, ".*<table.*>x</th>.*>1</td>.*>b</td>.*") %==% "")
})

assert("table is wrapped in a div for horizontal scroll", {
  html = build(list(data = list(x = 1:2)))
  (matches(html, '.*<div class="lt-wrap"><table.*</table></div>.*') %==% "")
})

assert("fmt_number formats decimals", {
  html = build(list(
    data = list(x = c(1.1, 2.346)),
    ops = list(list(type = "fmt_number", columns = list("x"), decimals = 2))
  ))
  (matches(html, ".*>1\\.10</td>.*>2\\.35</td>.*") %==% "")
})

assert("sub replaces NA", {
  html = build(list(
    data = list(x = c(1, NA)),
    ops = list(list(type = "sub", missing = "—"))
  ))
  (matches(html, ".*>—</td>.*") %==% "")
})

assert("separator row groups render correctly", {
  html = build(list(
    data = list(g = c("A", "A", "B"), v = 1:3),
    row_group = "g"
  ))
  (matches(html, '.*class="lt-row-group".*>A</th>.*>B</th>.*') %==% "")
})

assert("rowspan row groups render correctly", {
  html = build(list(
    data = list(g = c("A", "A", "B"), v = 1:3),
    row_group = list("g")
  ))
  (matches(html, '.*" rowspan="2">A</th>.*') %==% "")
})

assert("column spanner renders colspan", {
  html = build(list(
    data = list(a = 1, b = 2, c = 3),
    spanners = list(list(label = "AB", columns = list("a", "b")))
  ))
  (matches(html, '.*colspan="2".*>AB</th>.*') %==% "")
})

assert("footnotes render in tfoot", {
  html = build(list(
    data = list(x = 1),
    footnotes = list(list(
      text = "A note",
      location = list(type = "column_labels", columns = list("x"))
    ))
  ))
  (matches(html, '.*<tfoot class="lt-footer">.*> A note</td>.*') %==% "")
})

assert("merge with pattern", {
  html = build(list(
    data = list(a = "x", b = "y"),
    ops = list(list(type = "merge", columns = list("a", "b"), pattern = "{1} ({2})", hide = TRUE))
  ))
  (matches(html, '.*>x \\(y\\)</td>.*') %==% "")
})

assert("style with class and test", {
  html = build(list(
    data = list(x = c(1, 5)),
    ops = list(list(type = "style", columns = list("x"), test = "v => v > 3", class = "hi"))
  ))
  # "hi" applied to cell with 5 but not cell with 1
  (matches(html, '.*hi">5</td>.*') %==% "")
  (matches(html, '.*hi">1</td>.*') %==% html)
})

assert("sort by groups reorders rows", {
  html = build(list(
    data = list(g = c("B", "A", "B", "A"), v = c(1, 2, 3, 4)),
    row_group = list("g")
  ))
  # After sorting by g, A rows (2,4) come before B rows (1,3)
  (matches(html, ".*>2</td>.*>1</td>.*") %==% "")
})

assert("auto-format picks decimals from value width", {
  # Small values (<1) get up to 4 decimals; the big_mark separator is a
  # non-breaking space (U+00A0).
  html = build(list(data = list(x = c(0.123456, 0.987))))
  (matches(html, ".*>0\\.1235</td>.*>0\\.9870</td>.*") %==% "")
  # Large values are rounded to 0 decimals and grouped.
  html = build(list(data = list(x = c(1234.5, 9999.9))))
  (matches(html, ".*>1 235</td>.*>10 000</td>.*") %==% "")
})

assert("auto_format = FALSE leaves numbers untouched", {
  html = build(list(data = list(x = c(1.23456, 2.34567)), auto_format = FALSE))
  (matches(html, ".*>1\\.23456</td>.*>2\\.34567</td>.*") %==% "")
})

assert("per-cell style class merges with the column alignment class", {
  # Numeric columns get the "al-r" class; a style class on one cell must be
  # appended, not replace it.
  html = build(list(
    data = list(x = c(1, 5)),
    ops = list(list(type = "style", columns = list("x"), rows = list(2L), class = "hot"))
  ))
  (matches(html, '.*class="al-r hot">5</td>.*') %==% "")
  # The untouched cell keeps just the alignment class.
  (matches(html, '.*class="al-r">1</td>.*') %==% "")
})

assert("fmt_number with percent, big_mark, and minus sign", {
  html = build(list(
    data = list(x = c(0.1234, 12345.678)),
    ops = list(list(type = "fmt_number", columns = list("x"),
                    percent = TRUE, decimals = 1, big_mark = ","))
  ))
  (matches(html, ".*>12\\.3%</td>.*>1,234,567\\.8%</td>.*") %==% "")
  # Negative numbers render with a real minus sign (U+2212), not a hyphen.
  html = build(list(
    data = list(n = -1234567),
    ops = list(list(type = "fmt_number", columns = list("n"), big_mark = ","))
  ))
  (matches(html, ".*>−1,234,567</td>.*") %==% "")
})

assert("infinity renders as ∞, with minus sign depending on formatting", {
  # Raw (unformatted, non-numeric column) infinities use an ASCII hyphen.
  html = build(list(data = list(x = c(Inf, -Inf)), auto_format = FALSE))
  (matches(html, ".*>∞</td>.*>-∞</td>.*") %==% "")
  # Auto-formatted numeric column: minus becomes the typographic minus (U+2212).
  html = build(list(data = list(x = c(1.5, Inf, -Inf))))
  (matches(html, ".*>∞</td>.*>−∞</td>.*") %==% "")
  # Explicit fmt_number keeps ±∞ and uses the typographic minus.
  html = build(list(
    data = list(x = c(Inf, -Inf)),
    ops = list(list(type = "fmt_number", columns = list("x"), decimals = 2))
  ))
  (matches(html, ".*>∞</td>.*>−∞</td>.*") %==% "")
})

assert("fmt_number prefix and suffix", {
  html = build(list(
    data = list(price = c(1234.5, 678.9)),
    ops = list(list(
      type = "fmt_number", columns = list("price"),
      decimals = 2, big_mark = ",", prefix = "$"
    ))
  ))
  (matches(html, '.*>\\$1,234\\.50</td>.*>\\$678\\.90</td>.*') %==% "")
  # suffix
  html = build(list(
    data = list(weight = c(75, 80)),
    ops = list(list(
      type = "fmt_number", columns = list("weight"), suffix = " kg"
    ))
  ))
  (matches(html, '.*>75 kg</td>.*>80 kg</td>.*') %==% "")
  # prefix + percent
  html = build(list(
    data = list(rate = c(0.05, 0.12)),
    ops = list(list(
      type = "fmt_number", columns = list("rate"),
      decimals = 1, percent = TRUE, prefix = "+"
    ))
  ))
  (matches(html, '.*>\\+5\\.0%</td>.*>\\+12\\.0%</td>.*') %==% "")
})

assert("fmt_date formats ISO date strings", {
  html = build(list(
    data = list(event = c("A", "B"), date = c("2024-01-15", "2024-06-30")),
    ops = list(list(type = "fmt_date", columns = list("date"), method = "toISOString"))
  ))
  (matches(html, '.*>2024-01-15T00:00:00\\.000Z</td>.*>2024-06-30T00:00:00\\.000Z</td>.*') %==% "")
  # toUTCString
  html = build(list(
    data = list(date = "2024-01-15"),
    ops = list(list(type = "fmt_date", columns = list("date"), method = "toUTCString"))
  ))
  (matches(html, '.*>Mon, 15 Jan 2024 00:00:00 GMT</td>.*') %==% "")
  # null values are skipped
  html = build(list(
    data = list(date = list("2024-01-15", NULL)),
    ops = list(list(type = "fmt_date", columns = list("date"), method = "toISOString"))
  ))
  (matches(html, '.*>2024-01-15T00:00:00\\.000Z</td>.*></td>.*') %==% "")
})

assert("footnote on the title renders a marker in the caption", {
  html = build(list(
    data = list(x = 1),
    header = list(title = "T"),
    footnotes = list(list(
      text = "tn", location = list(type = "title", group = "title")
    ))
  ))
  (matches(html, '.*class="lt-title".*class="lt-fnref".*> tn</td>.*') %==% "")
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
  (matches(html, '.*Apple<sup class="lt-fnref".*> sn</td>.*') %==% "")
  (matches(html, ".*Banana<sup.*") %==% html)
})

assert("auto_label replaces separators with spaces in column headers", {
  html = build(list(data = list(Sepal.Length = c(5.1), Petal_Width = c(0.2))))
  (matches(html, '.*>Sepal Length</th>.*>Petal Width</th>.*') %==% "")
})

assert("auto_label = FALSE preserves raw column names", {
  html = build(list(data = list(Sepal.Length = c(5.1), Petal_Width = c(0.2)), auto_label = FALSE))
  (matches(html, '.*>Sepal\\.Length</th>.*>Petal_Width</th>.*') %==% "")
})

assert("merge drops a conditional block when its references are empty", {
  # "<<...>>" blocks are emitted only if all {n} refs are non-empty.
  html = build(list(
    data = list(a = "x", b = "", c = ""),
    ops = list(list(type = "merge", columns = list("a", "b", "c"),
                    pattern = "{1}<<({2}/{3})>>"))
  ))
  (matches(html, ".*>x</td>.*") %==% "")
  (matches(html, ".*\\(/\\).*") %==% html)
})

# Count the pages in a PDF file (each page object is "/Type /Page" not
# followed by "s", which would be "/Pages").
pdf_pages = function(f) {
  raw = readChar(f, file.info(f)$size, useBytes = TRUE)
  length(gregexpr("/Type\\s*/Page[^s]", raw)[[1]])
}

if (has_browser()) assert("lt_export() writes PDF and PNG by extension", {
  x = lt(data.frame(a = 1:2, b = c("x", "y")))
  pdf = tempfile(fileext = ".pdf")
  png = tempfile(fileext = ".png")
  on.exit(unlink(c(pdf, png)), add = TRUE)

  out = lt_export(x, pdf)
  (out %==% pdf)
  (file.exists(pdf))
  # PDF magic bytes: "%PDF"
  (rawToChar(readBin(pdf, "raw", 4L)) %==% "%PDF")
  # A cropped table fits on a single page.
  (pdf_pages(pdf) %==% 1L)

  lt_export(x, png)
  (file.exists(png))
  # PNG magic bytes: 0x89 "PNG"
  (readBin(png, "raw", 4L) %==% as.raw(c(0x89, 0x50, 0x4e, 0x47)))
})

# A taller/wider table (more rows than the PDF measurement used to account
# for) must still crop to one page: the table's caption border and footer
# spacing extend past the table's own border-box, so we measure the body's
# scroll size, not the table box.
if (has_browser()) assert("lt_export() crops a large table to one PDF page", {
  x = lt(head(iris, 20))
  pdf = tempfile(fileext = ".pdf")
  on.exit(unlink(pdf), add = TRUE)
  lt_export(x, pdf)
  (pdf_pages(pdf) %==% 1L)
})

if (has_browser() && requireNamespace("magick", quietly = TRUE))
  assert("lt_export() crops PNG tightly to the table size", {
    x = lt(head(mtcars))
    d = lt_measure(format(x, fragment = FALSE), c(8L, 8L), NULL)
    png = tempfile(fileext = ".png")
    on.exit(unlink(png), add = TRUE)
    lt_export(x, png, padding = 8)
    info = magick::image_info(magick::image_read(png))
    # The cropped image matches the measured content box exactly.
    (info$width %==% d[1L])
    (info$height %==% d[2L])
  })

# An explicit width overrides the measured width for both PDF and PNG,
# regardless of crop.
if (has_browser() && requireNamespace("magick", quietly = TRUE))
  assert("lt_export() honors an explicit width", {
    x = lt(head(mtcars))
    png = tempfile(fileext = ".png")
    on.exit(unlink(png), add = TRUE)
    lt_export(x, png, width = 400)
    (magick::image_info(magick::image_read(png))$width %==% 400L)
  })

# .html output bakes a static table via render_html().
if (has_node() || has_browser())
  assert("lt_export() writes a static HTML file", {
    html = tempfile(fileext = ".html")
    on.exit(unlink(html), add = TRUE)
    out = lt_export(lt(data.frame(a = 1:2, b = c("x", "y"))), html)
    (out %==% html)
    txt = paste(readLines(html), collapse = "")
    (matches(txt, ".*<table.*>b</th>.*>1</td>.*>x</td>.*") %==% "")
  })

# output = NA returns the HTML string instead of writing a file.
if (has_node() || has_browser())
  assert("lt_export(output = NA) returns the HTML string", {
    html = lt_export(lt(data.frame(a = 1:2, b = c("x", "y"))), NA)
    (is.character(html))
    (matches(paste(html, collapse = ""), ".*<table.*>1</td>.*>x</td>.*") %==% "")
  })

# method = "raw" writes the JavaScript-spec HTML (table built client-side),
# so the file carries the lt.js runtime and the spec, not a baked <table>.
assert('lt_export(method = "raw") emits the JS spec, no external tool', {
  html = lt_export(lt(data.frame(a = 1:2)), NA, method = "raw")
  (matches(paste(html, collapse = ""), ".*<script>.*LT.*</script>.*") %==% "")
})
