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
#' Interactivity needs the rows to be independent of each other, since it
#' reorders and hides them. Tables with row groups ([lt_group()]) or indentation
#' ([lt_indent()]) are rendered static (a console warning is emitted in the
#' browser). Column spanners ([lt_spanner()]) are no obstacle, nor are
#' row-specific styles or footnotes: those travel with their rows.
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
#' @param filter Whether to show a filter box under each column header, matching
#'   terms the same way as `search` but against that column only. A row is kept
#'   when it passes every filter and the search. Can also be a character vector
#'   of column names, to filter on those columns only.
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
  resize = FALSE, detail = NULL
) {
  # `sort` and `search` are always emitted (the object must be non-empty to
  # survive serialization); the rest only when asked for
  opts = list(sort = sort_keys(sort), search = search)
  if (!isFALSE(filter)) opts$filter = if (is.character(filter))
    list(columns = I(filter)) else TRUE
  if (!isFALSE(pager) && length(pager)) {
    sizes = unique(pager)
    sizes[!is.finite(sizes)] = 0  # the runtime reads 0 as "every row"
    opts$pager = I(as.integer(sizes))
  }
  if (isTRUE(resize)) opts$resize = TRUE
  if (!is.null(detail)) opts$detail = if (inherits(detail, 'JS_LITERAL'))
    detail else I(as.character(f_cols(detail, x$data)))
  x$interactive = opts
  x
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
