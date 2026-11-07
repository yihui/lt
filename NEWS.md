# CHANGES IN lt VERSION 0.6

- New book at <https://pkg.yihui.org/lt/book/> covering every feature, from the first table to Shiny, export, and the JavaScript runtime. The long examples `01-lt`, `02-lt-js`, and `03-gt` are now short overviews that point to it, and 36 new one-feature examples (`04-*` to `39-*`) cover the functions one at a time.

- Search and filter boxes in `lt_interactive()` read plain language: `price over 100, color is red or blue`, `between 5 and 10`, `is not`, `does not contain`, and `col value` for contains. Column labels may contain spaces; `,` and `;` separate conditions and `or` alternates them. A line under the box shows how the query was read, and boxes drop down random example queries built from the data (a column box gets ones for its own values), written in plain language as well as with operators (`price > 100`, `color == "red"`) and, in column boxes, expressions on `x` (`x > 5 && x < 9`); hovering a column box explains that `x` stands for the column's values. Text that isn't recognized is searched as typed. The parser is a standalone file, `lt-query.js`, usable outside lt.

- New `lt_serve()` makes an interactive table fetch its rows from a data URL, for data too big for the browser: the browser requests only the current page as JSON whenever the sort, filters, search, or page change. By default a local app (built on `xfun::new_app()`) serves the rows of the table in R; pass `url` to use your own server (e.g., backed by a database or Parquet files), whose request and response format is documented in `?lt_serve`. In Shiny, `render_lt()` serves the rows from the session itself.

- `lt_interactive(profile = TRUE)` shows a profile of each column: a mini bar chart of its values (a histogram for numbers and dates; one bar per category for text where at most half of the values are distinct, left blank otherwise) that highlights the rows kept by the filters, with summary statistics and the amount of missing values as a tooltip. Use `profile = "filter"` to put it in the column's filter popover instead of the header.

- Tables in a scrolling `lt_wrap()` box keep the whole header (spanners, labels, and interactive controls) in view while scrolling.

- Printing an `lt_tbl` in the viewer or browser fits the table to the window: a table too tall to fit scrolls inside its container (with the header kept in view) instead of adding a page scrollbar.

- `lt_interactive()` now defaults to `filter = "auto"`, `resize = TRUE`, and page sizes `c(10, 25, 50, Inf)` (the last size shows every row on one page, previously 100). Use `filter = FALSE` or `resize = FALSE` to turn those off.

- A `"select"` or `"checklist"` filter now offers the missing (`NA`) value as its own choice, so rows with missing values can be kept.

- `lt()` gains `show_types`: when `TRUE`, each column is tagged with its type (`<dbl>`, `<chr>`, `<fct>`, `<date>`, ...) under the column labels (followed by the filters of an interactive table).

- Added `lt_viewer()`, a data viewer for exploring a data frame: an interactive table with the data expression as the title, each column's type and profile, filters, and a column-visibility menu (thanks, @keaven, #56).

- With `auto_format = TRUE`, `lt()` shows date columns as `YYYY-MM-DD` and date-time columns as `YYYY-MM-DD HH:MM:SS` in the local time zone by default; use `lt_date()` to format them differently. In `lt_interactive()`, these columns sort chronologically and `filter = "auto"` gives them a range slider.

- `lt_interactive(filter = "auto")` picks each column's filter from its data: a range slider for numbers, a checklist for text with few distinct values, and a plain box otherwise.

- In `lt_interactive(filter = list(...))`, a column can be set to `FALSE` to leave it without a filter, e.g., `list("auto", id = FALSE)`.

- `lt_export(width = )` also accepts a CSS width string, e.g., `"min-content"` for the narrowest width that shows every column.

- `lt_interactive(hide = list(label = ))` shows the column-visibility menu as a labeled chip in the control bar instead of the eye icon.

- `lt_interactive(hide = NA)` now adds the column-visibility menu with all columns shown (`hide = TRUE` still works for now but will be dropped in the future).

- The control bar of an interactive table now lays out the search box first, then chips, then icons (column menu, CSV download), and the column menu button's tooltip reads "Show/Hide columns".

- Added `lt_input()` and `lt_update()`: an editable table as a Shiny input. Body cells of the chosen columns can be edited in the browser, and `input[[id]]` is the edited data frame.

- In `litedown::fuse()` documents, tables built from the same data frame now write the data to the output only once and refer to it from the other tables, which makes the output file smaller. This also works across child documents. Set the `lt.share_size` global option (in bytes) to share only data frames above that size.

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
