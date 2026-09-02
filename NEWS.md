# CHANGES IN lt VERSION 0.5

- Column selection now accepts predicate formulas: a one-sided formula whose right-hand side references the pronoun `.` (the character vector of column names) is evaluated as a predicate, and a logical result selects the matching names, e.g., `lt_spanner(x, "Time", columns = ~ endsWith(., "_time"))` or `lt_format(x, ~ grepl("_prob$", .), decimals = 2)`. A character result (e.g., `~ grep("_x$", ., value = TRUE)`) is used as-is. Bare-name formulas (e.g., `~ a + b`) continue to work unchanged. This applies to all functions that select columns.

- `lt_label()` now also accepts a single named list or named character vector mapping column names to labels (e.g., `lt_label(x, c(mpg = "Miles/Gallon", cyl = "Cylinders"))`), which is convenient when labels are computed programmatically. Named arguments (e.g., `lt_label(x, mpg = "Miles/Gallon")`) continue to work.

# CHANGES IN lt VERSION 0.4

- `lt_format()` gained a `sig_digits` argument to format numbers to a fixed number of significant digits (e.g., `lt_format(x, ~col, sig_digits = 3)`), which is useful for columns spanning several orders of magnitude. It is mutually exclusive with `decimals`.

- Missing (`NA`) cells now display an em dash (`—`) by default instead of an empty cell, so they are no longer confused with empty strings. Change the table-wide default with the `lt.missing` global option, e.g., `options(lt.missing = "n/a")`, or set it to `""` to keep `NA` cells blank. `lt_sub(missing =)` still overrides the text for specific columns.

# CHANGES IN lt VERSION 0.3

- `lt_width()` can set the width of the whole table via an unnamed argument, e.g., `lt_width("80%")`. It can be combined with named column widths.

- Column selection now accepts integer positions in addition to column names and one-sided formulas, e.g., `lt_align(x, 1:2, "center")` or `lt_spanner(x, "Grp", columns = 2:3)`. This applies to all functions that select columns (`lt_align()`, `lt_spanner()`, `lt_format()`, `lt_date()`, `lt_footnote()`, `lt_html()`, `lt_sub()`, `lt_merge()`, `lt_style()`, `lt_move()`, and `lt_group()`).

# CHANGES IN lt VERSION 0.2

- Added support for raw HTML in tables. Cell values and text are HTML-escaped by default; to emit raw HTML instead, mark whole body columns with `lt_html()`, or wrap the text passed to `lt_header()`, `lt_label()`, `lt_spanner()`, `lt_footnote()`, or `lt_note()` in `I()`.

- Added `lt_export()` to save an lt table to a file: `.html` (an HTML table, optionally baked to a static `<table>` via Node.js or a headless browser so it needs no JavaScript to view), `.pdf` (a vector PDF), or `.png` (a raster image). PDF and PNG are rendered in a headless Chromium browser and cropped tightly to the table by default.

# CHANGES IN lt VERSION 0.1

- Initial CRAN release.
