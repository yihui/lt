# Opt-in interactive table features, powered by lt-interactive.js. The options
# ride on a top-level `spec$interactive` object (not a body op) so the runtime
# reads them once; the assets are wired in only when a table opts in (render.R).

#' Enable interactive table features
#'
#' Make a table interactive in the browser: pagination, a table-wide search box,
#' click-to-sort column headers, per-column filter boxes, and resizable
#' columns. The features are handled client-side by an opt-in JavaScript
#' extension, loaded only for tables that call this function.
#'
#' Sorting and filtering respect the row structure. Separator row groups
#' ([lt_group()] with `sep = TRUE`, or manual groups) and indentation
#' ([lt_indent()]) are honored: sorting and filtering happen *within* each group
#' or subtree, the groups keep their order, a group whose rows all filter out
#' drops its header, and an indented child keeps its ancestors visible for
#' context. A rowspan row group ([lt_group()] with its default rowspan rendering)
#' is the one case still rendered static (a console warning is emitted in the
#' browser), since the spanning cells cannot survive a reorder. Column spanners
#' ([lt_spanner()]) are no obstacle either, nor are row-specific styles or
#' footnotes: those travel with their rows.
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
#'   `"select"` for a value dropdown, or `"range"` for a two-thumb range slider
#'   (the dropdown's choices and the slider's ends are taken from the column's
#'   data). For a custom label or hand-set options, pass a list instead of the
#'   string, e.g. `list(type = "select", label = "Cylinders")` or
#'   `list(type = "range", min = 0, max = 100)`. One *unnamed* entry in the list
#'   is the default applied to every other visible column, so
#'   `list(TRUE, cyl = "select")` boxes every column but gives `cyl` a dropdown.
#'   A typed filter renders as a funnel + popover (holding the widget *and* an
#'   expression box, kept in sync) under its column header, or — when the column
#'   is hidden from the table (e.g. with [lt_hide()]) — as a chip in the control
#'   bar, a natural way to offer a control for a value you don't show.
#' @param pager The page sizes to offer, as a vector of row counts; the
#'   first one is used initially. Paging shows that many of the filtered and
#'   sorted rows at a time, with a pager (first, previous, next, last), the row
#'   range, and (for more than one size) a selector below the table. `Inf` is a
#'   valid size (every row on one page), offered as `∞` in the selector. Use
#'   `FALSE` or `NULL` to show all rows with no pager at all.
#' @param resize Whether to let the reader drag a column's right edge to resize
#'   it (double-clicking the edge fits the column to its content). Widening a
#'   column widens the table, leaving the other columns as they are. Initial
#'   widths can be set with [lt_width()].
#' @param hide Column-visibility control: an eye button at the start of the
#'   search row opens a checklist of every column, where unchecking a column
#'   hides it (header and cells) and re-checking restores it. `TRUE` adds the
#'   menu with all columns shown; column names (a character vector or a one-sided
#'   formula, e.g. `~ x + y`) adds it with those columns hidden to begin with
#'   (every column is still listed, so any can be toggled). `NULL` (the default)
#'   adds no menu.
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
#' lt(head(mtcars)) |> lt_interactive(hide = c('hp', 'drat'))
#' lt(head(mtcars)) |> lt_interactive(hide = ~ hp + drat)  # same, as a formula
#' # an initial sort by cyl, then mpg descending within each (two equivalent
#' # forms: a character vector, or a formula)
#' lt(mtcars) |> lt_interactive(sort = c('cyl', '-mpg'))
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
lt_interactive = function(
  x, sort = TRUE, search = TRUE, filter = FALSE, pager = c(10, 25, 50, 100),
  resize = FALSE, hide = NULL, detail = NULL
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
  if (!is.null(hide) && !isFALSE(hide)) opts$hide = if (isTRUE(hide)) TRUE else
    list(hidden = I(as.character(f_cols(hide, x$data))))
  if (!is.null(detail)) opts$detail = if (inherits(detail, 'JS_LITERAL'))
    detail else I(as.character(f_cols(detail, x$data)))
  x$interactive = opts
  x
}

# Shape the `filter` argument for the client as { default?, cols? }. `TRUE` ->
# a box on every column (a `default`); a character vector -> boxes on just those
# columns; a named list -> each named column's own spec in `cols`, with one
# unnamed entry (if any) kept as the `default` for the other visible columns. The
# client resolves a typed spec's choices / range from the column data, so nothing
# here reads `x$data`.
normalize_filter = function(filter) {
  if (isTRUE(filter)) return(list(default = TRUE))
  if (is.character(filter))
    return(list(cols = stats::setNames(rep(list(TRUE), length(filter)), filter)))
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

# One column's filter spec: `TRUE` (a plain box) passes through; a `"select"` /
# `"range"` string becomes `list(type = ...)`; a list is a hand-set spec, its
# `choices` reshaped to {value, label} objects and `value` kept as a JSON array.
normalize_spec = function(spec) {
  if (isTRUE(spec)) return(TRUE)
  if (is.character(spec) && length(spec) == 1) return(list(type = spec))
  if (is.list(spec)) {
    if (!is.null(spec$choices)) spec$choices = choice_objs(spec$choices)
    if (!is.null(spec$value)) spec$value = I(spec$value)
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

# Normalize the `sort` argument. A logical passes through (enable or disable
# click-to-sort). An initial multi-column sort can be given as a character
# vector of column names or as a one-sided formula (e.g. `~ x + -y`); either
# way a leading `-` on a name, or a negated formula term, means descending. The
# names travel to the client as-is (the `-` convention is parsed there).
sort_keys = function(sort) {
  if (inherits(sort, 'formula')) sort = formula_sort(sort)
  if (!is.character(sort)) return(sort)
  I(sort)
}

# Flatten the right-hand side of a sort formula into `-`-prefixed column names,
# carrying the sign through nested `+`/`-` (unary `-` or the right side of a
# binary `-` flips a term to descending), e.g. `~ x + -y` and `~ x - y` both
# give `c('x', '-y')`.
formula_sort = function(f) {
  walk = function(e, neg = FALSE) {
    if (is.call(e)) {
      op = as.character(e[[1]])
      if (op == '+') return(c(walk(e[[2]], neg), walk(e[[3]], neg)))
      if (op == '-') return(if (length(e) == 3L)
        c(walk(e[[2]], neg), walk(e[[3]], !neg)) else walk(e[[2]], !neg))
    }
    stats::setNames(neg, as.character(e))
  }
  d = walk(f[[length(f)]])  # the right-hand side
  ifelse(d, paste0('-', names(d)), names(d))
}
