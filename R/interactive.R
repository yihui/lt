# Opt-in interactive features, powered by lt-interactive.js. Options ride on a
# top-level `spec$interactive` object (not a body op) so the runtime reads them
# once; assets are wired in only when a table opts in (render.R).

#' Enable interactive table features
#'
#' Make a table interactive in the browser: pagination, a table-wide search box,
#' click-to-sort column headers, per-column filter boxes, and resizable
#' columns. The features are handled client-side by an opt-in JavaScript
#' extension, loaded only for tables that call this function.
#'
#' Sorting and filtering respect the row structure, happening *within* each
#' group or subtree rather than across it. Separator row groups ([lt_group()]
#' with `sep = TRUE`, or manual groups) keep their order, and a group whose rows
#' all filter out drops its header. Indentation ([lt_indent()]) sorts siblings
#' under each parent, and an indented child keeps its ancestors visible for
#' context. Rowspan row groups ([lt_group()] with its default rowspan rendering)
#' sort and filter within each run and clicking a group header reorders its
#' blocks; with several group columns the view stays nested (an inner column
#' reorders only within its parent block), and the spanning cells are redrawn to
#' match.
#'
#' @inheritParams lt_align
#' @param sort Whether clicking a column header sorts the table by that column
#'   (cycling ascending, descending, then unsorted); shift-clicking adds a
#'   column as a further tie-breaker, so several columns can sort at once.
#'   Sorting uses the raw values, so numeric columns sort numerically. Can also
#'   request an initial sort by one or more columns, given either as a character
#'   vector of column names or as a one-sided formula (e.g. `~ x + -y`); a name
#'   prefixed with `-` (or a negated formula term) sorts that column descending,
#'   e.g. `c('g', '-x')` or `~ g + -x`.
#' @param search Whether to show a table-wide search box. A row is kept when
#'   any cell matches the term. Besides plain substring matching, a term that
#'   references the cell variable `x` (e.g. `x > 5` or `x != "A"`) is evaluated
#'   as a JavaScript expression against each cell's value.
#' @param filter The per-column filters. `TRUE` shows a filter box under every
#'   column header, matching terms the same way as `search` but against that
#'   column only (a row is kept when it passes every filter and the search). A
#'   character vector of column names restricts the boxes to those columns. A
#'   named list gives each named column its own filter: `TRUE` for a plain box,
#'   `"select"` for a value dropdown, `"range"` for a two-thumb range slider, or
#'   `"checklist"` for a popover of checkboxes that keeps the rows whose value is
#'   checked (the dropdown's / checklist's choices and the slider's ends are
#'   taken from the column's data). For a custom label or hand-set options, pass
#'   a list instead of the string, e.g. `list(type = "select", label =
#'   "Cylinders")` or `list(type = "range", min = 0, max = 100)`. One *unnamed*
#'   entry in the list
#'   is the default applied to every other visible column, so
#'   `list(TRUE, cyl = "select")` boxes every column but gives `cyl` a dropdown.
#'   A column with nothing to filter (every value blank) gets no box, even under
#'   that default.
#'   A typed filter renders as a funnel + popover (holding the widget *and* an
#'   expression box, kept in sync) under its column header, or — when the column
#'   is hidden from the table (e.g. with [lt_hide()]) — as a chip in the control
#'   bar, a natural way to offer a control for a value you don't show. Add `box =
#'   FALSE` to a typed spec's list to drop the expression box, restricting the
#'   column to the widget's own choices (e.g. a single-select dropdown with no
#'   custom set). The widget hides itself whenever a hand-typed expression
#'   outruns it (a value it cannot represent), so it never shows a value out of
#'   step with the box.
#' @param pager The page sizes to offer, as a vector of row counts; the
#'   first one is used initially. Paging shows that many of the filtered and
#'   sorted rows at a time, with a pager (first, previous, next, last), the row
#'   range, and (for more than one size) a selector below the table. `Inf` is a
#'   valid size (every row on one page), offered as an infinity symbol in the
#'   selector. The selector is omitted when the table has no more rows than the
#'   smallest page size (no size would split it), though the pager's nav and
#'   row-count readout stay, the latter being useful as a filter narrows the
#'   rows. Use `FALSE` or `NULL` to show all rows with no pager at all.
#' @param resize Whether to let the reader drag a column's right edge to resize
#'   it (double-clicking the edge fits the column to its content). Widening a
#'   column widens the table, leaving the other columns as they are. Initial
#'   widths can be set with [lt_width()].
#' @param hide Column-visibility control: an eye button at the start of the
#'   search row opens a checklist of every column, where unchecking a column
#'   hides it (header and cells) and re-checking restores it. `TRUE` adds the
#'   menu with all columns shown; column names (a character vector or a one-sided
#'   formula, e.g. `~ x + y`) adds it with those columns hidden to begin with
#'   (every column is still listed, so any can be toggled). To label the button
#'   instead of showing the eye icon, use a list with `label` (a string, shown as
#'   a chip at the far right of the control bar) and optionally `columns` (the
#'   columns hidden to begin with), e.g. `list(label = "Show/Hide columns")`.
#'   `NULL` (the default) adds no menu.
#' @param detail Row detail (drill-down). An expand caret is added to each row;
#'   clicking it reveals a table built from that row below it. Give the columns
#'   to show, as a character vector of names or a one-sided formula (e.g.
#'   `~ gear + carb`); their displayed (formatted) values are laid out as a
#'   one-row table. The columns can be ones hidden from the main table with
#'   [lt_hide()], a natural way to tuck extra fields into the detail. For full
#'   control, pass a JavaScript callback instead, wrapped in [js()]: it is
#'   called as `(row, index, display)` — `row` the raw values, `display` the
#'   formatted text, each keyed by column name — and returns a table spec, which
#'   may carry its own `interactive` field to make the detail table interactive.
#'   `NULL` (the default) adds no row detail.
#' @param download Whether to add a button that downloads the table as a CSV
#'   file. The file holds the current view (every row the filters and search
#'   keep, in sort order, across all pages) of the table's columns. `TRUE` adds
#'   the button with a default file name; a string sets the file name (a `.csv`
#'   extension is added if missing). For more control, pass a list with any of
#'   `file` (the file name) and `mode`: `"display"` (the default) exports the
#'   displayed cell text, while `"raw"` exports the underlying unformatted
#'   values (full precision, no thousands separators or percent signs), handier
#'   to re-import for analysis. Row detail (`detail`) is never included. `FALSE`
#'   (the default) adds no button.
#' @return `x` with interactivity enabled.
#' @export
#' @examples
#' lt(head(mtcars)) |> lt_interactive()
#' # search only, no click-to-sort or pagination
#' lt(head(mtcars)) |> lt_interactive(sort = FALSE, pager = FALSE)
#' # 5 rows at a time, or all of them, with a filter box on one column
#' lt(mtcars) |> lt_interactive(filter = 'cyl', pager = c(5, Inf))
#' # resizable columns
#' lt(head(mtcars)) |> lt_interactive(resize = TRUE)
#' # a column-visibility menu (all columns shown, or with some hidden to start)
#' lt(head(mtcars)) |> lt_interactive(hide = TRUE)
#' lt(head(mtcars)) |> lt_interactive(hide = ~ hp + drat)
#' # a labeled button instead of the eye icon
#' lt(head(mtcars)) |> lt_interactive(hide = list(label = 'Show/Hide columns'))
#' # an initial sort by cyl, then mpg descending within each
#' lt(mtcars) |> lt_interactive(sort = ~ cyl + -mpg)
#' # expandable row detail (drill-down): name the columns to show. Here gear and
#' # carb are hidden from the main table but revealed in the detail that appears
#' # when a row is expanded.
#' lt(head(mtcars)) |>
#'   lt_hide(~ gear + carb) |>
#'   lt_interactive(detail = ~ gear + carb)
#' # for full control, pass a JavaScript callback yourself: (raw row, index,
#' # displayed row); here showing the row number and mpg as the table displays it
#' lt(head(mtcars)) |> lt_interactive(
#'   detail = js('(row, i, d) => ({ data: { metric: ["row", "mpg"],
#'     value: [i, d.mpg] } })')
#' )
#' # a button to download the current view as a CSV file
#' lt(head(mtcars)) |> lt_interactive(download = TRUE)
#' lt(head(mtcars)) |> lt_interactive(download = 'cars.csv')
#' # export the raw (unformatted) values instead of the displayed text
#' lt(head(mtcars)) |> lt_interactive(download = list(file = 'cars.csv', mode = 'raw'))
lt_interactive = function(
  x, sort = TRUE, search = TRUE, filter = FALSE, pager = c(10, 25, 50, 100),
  resize = FALSE, hide = NULL, detail = NULL, download = FALSE
) {
  # `sort` and `search` are always emitted (the object must be non-empty to
  # survive serialization); the rest only when asked for
  opts = list(sort = sort_keys(sort), search = search)
  if (!isFALSE(filter)) opts$filter = normalize_filter(filter)
  if (!isFALSE(pager) && length(pager)) {
    sizes = unique(pager)
    sizes[!is.finite(sizes)] = 0  # the runtime reads 0 as "every row"
    opts$pager = I(as.integer(sizes))
  }
  if (isTRUE(resize)) opts$resize = TRUE
  if (!is.null(hide) && !isFALSE(hide)) {
    label = NULL
    if (is.list(hide)) {
      label = hide$label
      hide = hide$columns %||% TRUE
    }
    opts$hide = if (isTRUE(hide) && is.null(label)) TRUE else drop_null(list(
      label = label,
      hidden = if (!isTRUE(hide)) I(as.character(f_cols(hide, x$data)))
    ))
  }
  if (!is.null(detail)) opts$detail = if (inherits(detail, 'JS_LITERAL'))
    detail else I(as.character(f_cols(detail, x$data)))
  opts$download = download_opt(download)
  x$interactive = opts
  x
}

# Shape `download` for the client: a bare file name (or `TRUE`) when only the
# name differs, else an object of non-default slots; a plain download never
# serializes a `mode` key.
download_opt = function(download) {
  if (is.null(download) || isFALSE(download)) return()
  if (isTRUE(download)) return(TRUE)
  if (is.character(download)) download = list(file = download)
  mode = download$mode
  if (identical(mode, 'display')) mode = NULL  # the default; keep it implicit
  if (is.null(mode)) return(download$file %||% TRUE)
  drop_null(list(file = download$file, mode = mode))
}

# Shape `filter` for the client as { default?, cols? }. `TRUE` -> a box on
# every column (`default`); a character vector -> boxes on just those columns;
# a named list -> each named column's own spec in `cols`, one unnamed entry (if
# any) kept as `default` for other visible columns. The client resolves a typed
# spec's choices / range from column data, so nothing here reads `x$data`.
normalize_filter = function(filter) {
  if (isTRUE(filter)) return(list(default = TRUE))
  if (is.character(filter))
    return(list(cols = set_names(rep(list(TRUE), length(filter)), filter)))
  if (is.list(filter)) {
    nm = names(filter)
    if (is.null(nm)) nm = rep('', length(filter))
    out = list(); cols = list()
    for (i in seq_along(filter)) {
      spec = normalize_spec(filter[[i]])
      if (nzchar(nm[i])) cols[[nm[i]]] = spec else out$default = spec
    }
    if (length(cols)) out$cols = cols
    return(out)
  }
  TRUE
}

# One column's filter spec: `TRUE` (plain box) passes through; a `"select"` /
# `"range"` / `"checklist"` string becomes `list(type = ...)`; a list is a
# hand-set spec, `choices` reshaped to {value, label} objects, `value` (range)
# / `selected` (checklist) default kept as a JSON array.
normalize_spec = function(spec) {
  if (isTRUE(spec)) return(TRUE)
  if (is.character(spec) && length(spec) == 1) return(list(type = spec))
  if (is.list(spec)) {
    if (!is.null(spec$choices)) spec$choices = choice_objs(spec$choices)
    if (!is.null(spec$value)) spec$value = I(spec$value)
    if (!is.null(spec$selected)) spec$selected = I(spec$selected)
    return(spec)
  }
  stop('invalid filter spec: ', toString(spec))
}

# A dropdown's `choices` as {value, label} objects; names, if any, are the labels.
choice_objs = function(ch) {
  labs = names(ch)
  if (is.null(labs)) labs = as.character(ch)
  lapply(seq_along(ch), function(i)
    list(value = as.character(ch[[i]]), label = labs[i]))
}

# Normalize `sort`. A logical passes through (enable/disable click-to-sort).
# An initial multi-column sort is a character vector of column names or a
# one-sided formula (e.g. `~ x + -y`); a leading `-` on a name, or a negated
# formula term, means descending. Names travel to the client as-is (the client
# parses `-`).
sort_keys = function(sort) {
  if (inherits(sort, 'formula')) sort = formula_sort(sort)
  if (!is.character(sort)) return(sort)
  I(sort)
}

# Flatten a sort formula's right-hand side into `-`-prefixed column names,
# carrying the sign through nested `+`/`-` (unary `-` or the right side of a
# binary `-` flips to descending): `~ x + -y` and `~ x - y` both give
# `c('x', '-y')`.
formula_sort = function(f) {
  walk = function(e, neg = FALSE) {
    if (is.call(e)) {
      op = as.character(e[[1]])
      if (op == '+') return(c(walk(e[[2]], neg), walk(e[[3]], neg)))
      if (op == '-') return(if (length(e) == 3L)
        c(walk(e[[2]], neg), walk(e[[3]], !neg)) else walk(e[[2]], !neg))
    }
    set_names(neg, as.character(e))
  }
  d = walk(f[[length(f)]])  # the right-hand side
  ifelse(d, paste0('-', names(d)), names(d))
}
