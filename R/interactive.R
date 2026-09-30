# Opt-in interactive table features, powered by lt-interactive.js. The options
# ride on a top-level `spec$interactive` object (not a body op) so the runtime
# reads them once; the assets are wired in only when a table opts in (render.R).

#' Enable Interactive Table Features
#'
#' Make a table interactive in the browser: a table-wide search box,
#' click-to-sort column headers, per-column filter boxes, and pagination. The
#' features are handled client-side by an opt-in JavaScript extension, loaded
#' only for tables that call this function.
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
#' @param paginate Whether to show one page of rows at a time, with a pager
#'   (first, previous, next, last), the row range, and a page size selector
#'   below the table. Paging applies to the filtered and sorted rows.
#' @param page_size The number of rows per page.
#' @param page_size_options The page sizes offered in the selector (`page_size`
#'   is always offered, and the options are sorted).
#' @return `x` with interactivity enabled.
#' @export
#' @examples
#' lt(head(mtcars)) |> lt_interactive()
#' # search only, no click-to-sort
#' lt(head(mtcars)) |> lt_interactive(sort = FALSE)
#' # 10 rows at a time, with a filter box on one column
#' lt(mtcars) |> lt_interactive(filter = 'cyl', paginate = TRUE)
lt_interactive = function(
  x, sort = TRUE, search = TRUE, filter = FALSE, paginate = FALSE,
  page_size = 10, page_size_options = c(10, 25, 50, 100)
) {
  # `sort` and `search` are always emitted (the object must be non-empty to
  # survive serialization); the rest only when asked for
  opts = list(sort = sort, search = search)
  if (!isFALSE(filter)) opts$filter = if (is.character(filter))
    list(columns = I(filter)) else TRUE
  if (!isFALSE(paginate)) opts$paginate = list(
    pageSize = as.integer(page_size),
    # offer the current size too, so the selector never shows a stale value
    pageSizeOptions = I(sort(unique(as.integer(c(page_size, page_size_options)))))
  )
  x$interactive = opts
  x
}
