# lt_export(): PDF/PNG/HTML output, single-page cropping, user CSS, explicit
# width, and the raw/tidy HTML variants.

# Count the pages in a PDF file (each page object is "/Type /Page" not
# followed by "s", which would be "/Pages").
pdf_pages = function(f) {
  raw = readChar(f, file.info(f)$size, useBytes = TRUE)
  length(gregexpr("/Type\\s*/Page[^s]", raw)[[1]])
}

assert("lt_export() writes PDF and PNG by extension", {
  x = lt(data.frame(a = 1:2, b = c("x", "y")))
  pdf = tempfile(fileext = ".pdf")
  png = tempfile(fileext = ".png")
  on.exit(unlink(c(pdf, png)), add = TRUE)

  out = lt_export(x, pdf)
  (out %==% pdf)
  (file.exists(pdf))
  # PDF magic bytes: "%PDF"
  (rawToChar(readBin(pdf, "raw", 4L)) %==% "%PDF")

  lt_export(x, png)
  (file.exists(png))
  # PNG magic bytes: 0x89 "PNG"
  (readBin(png, "raw", 4L) %==% as.raw(c(0x89, 0x50, 0x4e, 0x47)))
})

# Taller table must still crop to one page: caption border and footer spacing
# extend past the table's border-box, so measure the body's scroll size.
assert("lt_export() crops a large table to one PDF page", {
  x = lt(head(iris, 20))
  pdf = tempfile(fileext = ".pdf")
  on.exit(unlink(pdf), add = TRUE)
  lt_export(x, pdf)
  (pdf_pages(pdf) %==% 1L)
})

# Wide table must crop to one page. scrollWidth floors the fractional width;
# pinning to it left the body sub-pixel too narrow, wrapping a cell and
# spilling onto a second page (macOS only). lt_measure() rounds up by 1px.
assert("lt_export() crops a wide table to one PDF page", {
  # many long labels give a fractional natural width
  x = lt(as.data.frame(matrix(
    1:32, 4, 8, dimnames = list(NULL, paste0("a_long_column_label_", 1:8))
  )))
  pdf = tempfile(fileext = ".pdf")
  on.exit(unlink(pdf), add = TRUE)
  lt_export(x, pdf)
  (pdf_pages(pdf) %==% 1L)
})

# Fractional height must crop to one page. scrollHeight is rounded, but the
# 0.85em footer makes the body slightly taller (e.g., 316.39px), so a page box
# of exactly scrollHeight overflowed to a second page (macOS only).
# lt_measure() rounds up by 1px too.
assert("lt_export() crops a table with a fractional height to one PDF page", {
  x = lt(head(mtcars)) |>
    lt_footnote("Source: 1974 Motor Trend US magazine.", "title") |>
    lt_footnote("Miles per gallon.", "column", "mpg")
  pdf = tempfile(fileext = ".pdf")
  on.exit(unlink(pdf), add = TRUE)
  lt_export(x, pdf)
  (pdf_pages(pdf) %==% 1L)
})

if (xfun::loadable("magick"))
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

# Relative user-CSS path must still apply when rendering from the temp
# directory: lt_export() absolutizes existing local files.
if (xfun::loadable("magick"))
  assert("lt_export() applies a relative user-CSS path", {
    d = tempfile(); dir.create(d)
    on.exit(unlink(d, recursive = TRUE), add = TRUE)
    writeLines(".lt-table td { background: #ff0000 }", file.path(d, "red.css"))
    owd = setwd(d); on.exit(setwd(owd), add = TRUE)
    x = lt(data.frame(a = 1:2)) |> lt_css("red.css")
    png = tempfile(fileext = ".png")
    on.exit(unlink(png), add = TRUE)
    lt_export(x, png)
    # the styled cells make the cropped image predominantly red
    hist = magick::image_data(magick::image_read(png), "rgba")
    (any(hist[1L, , ] == as.raw(0xff) & hist[2L, , ] == as.raw(0x00)))
  })

# An explicit width overrides the measured width for both PDF and PNG,
# regardless of crop.
if (xfun::loadable("magick"))
  assert("lt_export() honors an explicit width", {
    x = lt(head(mtcars))
    png = tempfile(fileext = ".png")
    on.exit(unlink(png), add = TRUE)
    lt_export(x, png, width = 400)
    (magick::image_info(magick::image_read(png))$width %==% 400L)
  })

# .html output bakes a static table via lt_static().
if (can_bake())
  assert("lt_export() writes a static HTML file", {
    html = tempfile(fileext = ".html")
    on.exit(unlink(html), add = TRUE)
    out = lt_export(lt(data.frame(a = 1:2, b = c("x", "y"))), html)
    (out %==% html)
    txt = readLines(html)
    (has_match(txt, "<table.*>b</th>.*>1</td>.*>x</td>"))
  })

# output = NA returns the HTML string instead of writing a file.
if (can_bake())
  assert("lt_export(output = NA) returns the HTML string", {
    html = lt_export(lt(data.frame(a = 1:2, b = c("x", "y"))), NA)
    (has_match(html, "<table.*>1</td>.*>x</td>"))
  })

# method = "raw" writes the JavaScript-spec HTML (table built client-side),
# so the file carries the lt.js runtime and the spec, not a baked <table>.
assert('lt_export(method = "raw") emits the JS spec, no external tool', {
  html = lt_export(lt(data.frame(a = 1:2)), NA, method = "raw")
  (has_match(html, "<script>.*LT.*</script>"))
})

# tidy = TRUE pretty-prints the baked <table>: multi-line, indented, with each
# structural tag and cell on its own line.
if (can_bake())
  assert("lt_export(tidy = TRUE) pretty-prints the baked table", {
    html = lt_export(
      lt(data.frame(a = 1:2, b = c("x", "y"))), NA, fragment = TRUE,
      css = FALSE, tidy = TRUE
    )
    # the baked HTML comes back split across lines (joined at write time)
    lines = unlist(strsplit(html, "\n"))
    (any(grepl("^  <table", lines)))         # table indented under the wrap
    (any(grepl("^      <tr>$", lines)))       # rows on their own line
    (any(grepl("^        <td[ >].*</td>$", lines)))  # each cell a single line
  })
