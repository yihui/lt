# Opt-in interactive table features, powered by lt-interactive.js. The options
# ride on a top-level `spec$interactive` object (not a body op) so the runtime
# reads them once; the assets are wired in only when a table opts in (render.R).

#' Enable Interactive Table Features
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
#'   be a character vector of column names, giving an initial sort by those
#'   columns in order (ascending, or descending for a name prefixed with `-`,
#'   e.g. `c('g', '-x')`).
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
#' # an initial sort by cyl, then mpg descending within each
#' lt(mtcars) |> lt_interactive(sort = c('cyl', '-mpg'))
lt_interactive = function(
  x, sort = TRUE, search = TRUE, filter = FALSE, pager = c(10, 25, 50, 100),
  resize = FALSE
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
  x$interactive = opts
  x
}

# Normalize the `sort` argument. A logical passes through (enable or disable
# click-to-sort); a character vector is an initial multi-column sort, each name
# ascending unless prefixed with `-` for descending, carried to the client as a
# list of `{col, dir}` keys applied in order.
sort_keys = function(sort) {
  if (!is.character(sort)) return(sort)
  desc = startsWith(sort, '-')
  cols = ifelse(desc, substring(sort, 2L), sort)
  unname(Map(function(col, d) list(col = col, dir = if (d) 'desc' else 'asc'),
             cols, desc))
}
