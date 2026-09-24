# Opt-in interactive table features, powered by lt-interactive.js. The options
# ride on a top-level `spec$interactive` object (not a body op) so the runtime
# reads them once; the assets are wired in only when a table opts in (render.R).

#' Enable Interactive Table Features
#'
#' Make a table interactive in the browser: a table-wide search box and
#' click-to-sort column headers. The features are handled client-side by an
#' opt-in JavaScript extension, loaded only for tables that call this function.
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
#' @return `x` with interactivity enabled.
#' @export
#' @examples
#' lt(head(mtcars)) |> lt_interactive()
#' # search only, no click-to-sort
#' lt(head(mtcars)) |> lt_interactive(sort = FALSE)
lt_interactive = function(x, sort = TRUE, search = TRUE) {
  x$interactive = list(sort = sort, search = search)
  x
}
