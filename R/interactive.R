# Opt-in interactive table features, powered by lt-interactive.js. The options
# ride on a top-level `spec$interactive` object (not a body op) so the runtime
# reads them once; the assets are wired in only when a table opts in (render.R).

#' Enable Interactive Table Features
#'
#' Make a table interactive in the browser: pagination, a table-wide search box,
#' click-to-sort column headers, and per-column filter boxes. The features are
#' handled client-side by an opt-in JavaScript extension, loaded only for tables
#' that call this function.
#'
#' Interactivity targets flat tables. Tables with row groups
#' ([lt_group()]), spanners ([lt_spanner()]), or row-indexed operations are
#' rendered static (a console warning is emitted in the browser).
#'
#' @inheritParams lt_align
#' @param sort Whether clicking a column header sorts the table by that column
#'   (cycling ascending, descending, then unsorted). Sorting uses the raw
#'   values, so numeric columns sort numerically.
#' @param search Whether to show a table-wide search box. A row is kept when
#'   any cell matches the term. Besides plain substring matching, a term that
#'   references the cell variable `x` (e.g. `x > 5` or `x != "A"`) is evaluated
#'   as a JavaScript expression against each cell's value.
#' @param filter Whether to show a filter box under each column header, matching
#'   terms the same way as `search` but against that column only. A row is kept
#'   when it passes every filter and the search. Can also be a character vector
#'   of column names, to filter on those columns only.
#' @param page_sizes The page sizes to offer, as a vector of row counts; the
#'   first one is used initially. Paging shows that many of the filtered and
#'   sorted rows at a time, with a pager (first, previous, next, last), the row
#'   range, and (for more than one size) a selector below the table. Use `FALSE`
#'   or `NULL` to show all rows on one page.
#' @return `x` with interactivity enabled.
#' @export
#' @examples
#' lt(head(mtcars)) |> lt_interactive()
#' # search only, no click-to-sort or pagination
#' lt(head(mtcars)) |> lt_interactive(sort = FALSE, page_sizes = NULL)
#' # 5 rows at a time (no other size offered), with a filter box on one column
#' lt(mtcars) |> lt_interactive(filter = 'cyl', page_sizes = 5)
lt_interactive = function(
  x, sort = TRUE, search = TRUE, filter = FALSE,
  page_sizes = c(10, 25, 50, 100)
) {
  # `sort` and `search` are always emitted (the object must be non-empty to
  # survive serialization); the rest only when asked for
  opts = list(sort = sort, search = search)
  if (!isFALSE(filter)) opts$filter = if (is.character(filter))
    list(columns = I(filter)) else TRUE
  if (!isFALSE(page_sizes) && length(page_sizes))
    opts$paginate = I(unique(as.integer(page_sizes)))
  x$interactive = opts
  x
}
