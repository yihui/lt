# CHANGES IN lt VERSION 0.5

- Added `lt_interactive()` to make a table interactive in the browser: click-to-sort column headers (shift-click adds a column as a further tie-breaker, so several columns can sort at once, and `sort` can request an initial sort by one or more columns), a table-wide search box, per-column filters (`filter`, which besides plain filter boxes accepts typed `"select"` dropdown and `"range"` slider controls — given as a named list such as `list(cyl = "select", mpg = "range")`, with one unnamed entry as the default for the other columns — each paired with an expression box that stays in sync, rendered as a funnel under the column header or, for a column hidden from the table, as a chip in the control bar), pagination (`pager`, on by default, and `Inf` is a valid page size meaning all rows), resizable columns (`resize`), a column-visibility menu (`hide`) whose eye button toggles columns on and off, and expandable row detail (`detail`), where clicking a caret reveals a drill-down table built from that row. Searching and filtering match the displayed text case-insensitively, with a leading `!` to negate; a term that mentions `x` (e.g., `x > 5`) is evaluated as a JavaScript expression against the raw cell values instead. The controls are rows of the table itself, so they are exactly as wide as it is. All of this is handled client-side by an extension (`lt-interactive.js`/`.css`) that is only loaded for tables that call `lt_interactive()`, so the base runtime stays small for everyone else. Separator row groups and row indentation are honored: sorting and filtering happen within each group or subtree, the groups keep their order, a group whose rows all filter out drops its header, and an indented child keeps its ancestors visible; only a rowspan row group (the default `lt_group()` rendering) is still left static, since its spanning cells cannot survive a reorder.

- Added `lt_errorbar()`, `lt_sparkline()`, and `lt_dotplot()` to draw inline plots in table cells. `lt_errorbar()` draws a point estimate with lower/upper bounds (several series can be stacked in one cell, with a colored footer legend and an optional reference line and axis); `lt_sparkline()` draws a per-row line or bar chart from a list-column or several numeric columns read across the row; and `lt_dotplot()` draws one dot per column on a shared scale, optionally colored with a legend and staggered onto separate tracks so near-equal values do not overlap. All three are lightweight: only the numbers travel to the client and the SVG is drawn in the browser, so an interactive table (`lt_interactive()`) draws only the rows on the current page.

- Interactive tables now expose a controller on the rendered table element as `el._lt`, whose `filter(id, fn)` method installs a custom predicate for a column. External widgets (e.g. a dropdown or range slider built outside the table) can drive filtering through it, without the built-in filter boxes. The row object handed to the predicate carries *every* column, including ones hidden from the table, so a widget can filter on a hidden helper column.

- The lt.js runtime gained `LT.render(el, spec)`, which renders a spec into a container element at any time (unlike `LT.build()`, which has to be called from an inline `<script>` while the page is parsing). This is for tables built on demand, e.g., a table rendered when the reader expands a row.

- Column selection now accepts predicate formulas: a one-sided formula whose right-hand side references the pronoun `.` (the character vector of column names) is evaluated as a predicate, and a logical result selects the matching names, e.g., `lt_spanner(x, "Time", columns = ~ endsWith(., "_time"))` or `lt_format(x, ~ grepl("_prob$", .), decimals = 2)`. A character result (e.g., `~ grep("_x$", ., value = TRUE)`) is used as-is. Bare-name formulas (e.g., `~ a + b`) continue to work unchanged. This applies to all functions that select columns.

- `lt_label()` now also accepts a single named list or named character vector mapping column names to labels (e.g., `lt_label(x, c(mpg = "Miles/Gallon", cyl = "Cylinders"))`), which is convenient when labels are computed programmatically. Named arguments (e.g., `lt_label(x, mpg = "Miles/Gallon")`) continue to work.

- `lt_spanner()` no longer requires its `columns` to be listed in the table's visual (left-to-right) order. The columns of an explicit spanner are now reordered to match the final body order (after any `lt_move()`) before rendering, so a spanner is drawn correctly regardless of the order in which its columns were listed. This also makes predicate selectors (e.g., `columns = ~ endsWith(., "_time")`) safe to use for spanners. The columns must still be contiguous in the table body.

- `lt_export()` to PDF or PNG no longer silently drops a stylesheet attached by `lt_css()` with a relative path (e.g. `lt_css(x, "times.css")`). Those renders re-root the page to a temporary directory, where a relative link no longer resolved; existing local stylesheet files are now absolutized for that render pass only (the HTML output keeps relative paths, which are more portable; thanks, @tgerke, #7).

- `lt_export()` no longer spills a cropped PDF onto a second page (holding a repeated header and the footnotes) when the rendered height of the table is fractional, e.g., with two footnote rows. The measured height is now rounded up by 1px, as the width already was.

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
