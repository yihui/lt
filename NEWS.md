# CHANGES IN lt VERSION 0.6

- Added `lt_input()` and `lt_update()`: an editable table as a Shiny input. Body cells of the chosen columns can be edited in the browser, and `input[[id]]` is the edited data frame.

- In `litedown::fuse()` documents, multiple tables built from the same data frame now encode the data once and share it instead of repeating it in every table, including across child documents. Set the `lt.share_size` global option (in bytes) to share only data frames above that size.

# CHANGES IN lt VERSION 0.5

- Added `lt_interactive()` to make a table interactive in the browser: click-to-sort headers, a search box, per-column filters (plain, or typed dropdown/range/checklist widgets), pagination, column resizing, a column-visibility menu, expandable row detail, and a CSV download of the current view. Everything runs client-side via an extension loaded only for opted-in tables, and sorting and filtering stay within each row group or subtree.

- Added `lt_errorbar()`, `lt_sparkline()`, and `lt_dotplot()` to draw lightweight inline plots (error bars, line/bar sparklines, dot plots) in table cells: only the numbers travel to the client and the SVG is drawn in the browser.

- Interactive tables expose a controller `el._lt` for driving filters and row detail from external widgets, plus `LT.ui` helpers (`popover()`, `checklist()`, `chip()`) and a new `LT.render(el, spec)` for building such widgets and on-demand tables.

- Column selection now accepts predicate formulas referencing the pronoun `.` (the column names), e.g. `~ endsWith(., "_time")`, in all functions that select columns.

- `lt_label()` now also accepts a named list or vector mapping column names to labels.

- Added `lt_wrap()` to set HTML attributes on the `.lt-wrap` container, a hook for scoping custom CSS or sizing a table.

- `lt_spanner()` no longer requires its `columns` in visual order; they are reordered to match the body before rendering (they must still be contiguous).

- `lt_export()` no longer drops a `lt_css()` stylesheet attached by a relative path (thanks, @tgerke, #7).

- `lt_export()` no longer spills a cropped PDF onto a second page when the table height is fractional.

# CHANGES IN lt VERSION 0.4

- `lt_format()` gained a `sig_digits` argument to format numbers to a fixed number of significant digits (e.g., `lt_format(x, ~col, sig_digits = 3)`), which is useful for columns spanning several orders of magnitude. It is mutually exclusive with `decimals`.

- Missing (`NA`) cells now display an em dash (`—`) by default instead of an empty cell, so they are no longer confused with empty strings. Change the table-wide default with the `lt.missing` global option, e.g., `options(lt.missing = "n/a")`, or set it to `""` to keep `NA` cells blank. `lt_sub(missing =)` still overrides the text for specific columns.

# CHANGES IN lt VERSION 0.3

- `lt_width()` can set the width of the whole table via an unnamed argument, e.g., `lt_width("80%")`. It can be combined with named column widths.

- The `name = value` setters (`lt_label()`, `lt_width()`, `lt_css()`, `lt_wrap()`) accept their names and values as a single unnamed `list(names, values)` of two parallel vectors, e.g., `lt_label(x, list(cols, labels))`. This supplies the names from a variable, which `name = value` can't express (its names must be literals). They also all accept a single named vector or list (previously only `lt_label()` did).

- Column selection now accepts integer positions in addition to column names and one-sided formulas, e.g., `lt_align(x, 1:2, "center")` or `lt_spanner(x, "Grp", columns = 2:3)`. This applies to all functions that select columns (`lt_align()`, `lt_spanner()`, `lt_format()`, `lt_date()`, `lt_footnote()`, `lt_html()`, `lt_sub()`, `lt_merge()`, `lt_style()`, `lt_move()`, and `lt_group()`).

# CHANGES IN lt VERSION 0.2

- Added support for raw HTML in tables. Cell values and text are HTML-escaped by default; to emit raw HTML instead, mark whole body columns with `lt_html()`, or wrap the text passed to `lt_header()`, `lt_label()`, `lt_spanner()`, `lt_footnote()`, or `lt_note()` in `I()`.

- Added `lt_export()` to save an lt table to a file: `.html` (an HTML table, optionally baked to a static `<table>` via Node.js or a headless browser so it needs no JavaScript to view), `.pdf` (a vector PDF), or `.png` (a raster image). PDF and PNG are rendered in a headless Chromium browser and cropped tightly to the table by default.

# CHANGES IN lt VERSION 0.1

- Initial CRAN release.
