# CHANGES IN lt VERSION 0.2

- Added support for raw HTML in tables. Cell values and text are HTML-escaped by default; to emit raw HTML instead, mark whole body columns with `lt_html()`, or wrap the text passed to `lt_header()`, `lt_label()`, `lt_spanner()`, `lt_footnote()`, or `lt_note()` in `I()`.

- Added `lt_export()` to save an lt table to a file: `.html` (an HTML table, optionally baked to a static `<table>` via Node.js or a headless browser so it needs no JavaScript to view), `.pdf` (a vector PDF), or `.png` (a raster image). PDF and PNG are rendered in a headless Chromium browser and cropped tightly to the table by default.

# CHANGES IN lt VERSION 0.1

- Initial CRAN release.
