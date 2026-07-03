#' lt: Lightweight Tables via JSON Specs and JavaScript
#'
#' A small grammar of tables. A table is a data frame plus a list of
#' operations (title, spanner, footnote, ...); the operations are serialized to
#' a JSON spec and applied to a plain semantic HTML table by a tiny vanilla
#' JavaScript runtime at render time.
#'
#' @name lt-package
#' @keywords internal
'_PACKAGE'

#' Create a Table Specification
#'
#' Entry point of the lightweight grammar of tables. Returns an object (a
#' list) that records the data plus a list of table-modifying operations. The
#' object is rendered to HTML by [format()] (called automatically by the
#' print method).
#'
#' @param data A data frame (or anything coercible to one).
#' @param ... Arguments passed to methods.
#' @param auto_format Whether to automatically format numeric columns (rounding,
#'   thousand separators, percentage detection). Set to `FALSE` to disable
#'   for the whole table; use [lt_format()] on specific columns to disable
#'   selectively.
#' @param auto_label Whether to automatically clean column names for display
#'   by replacing separators (`.` and `_`) with spaces. Set to `FALSE` to
#'   show raw column names.
#' @section Interactivity:
#' When a cell value has been formatted (e.g., by auto-formatting or
#' [lt_format()]), the original value is stored in the cell's `title`
#' attribute and shown as a tooltip on hover. Additionally:
#'
#' - `Alt + Click` on a table toggles display of all raw values in that table.
#' - `Alt + Double-Click` on a table toggles raw values globally (all tables
#'   on the page).
#'
#' Raw values are shown as `(value)` after the formatted text, highlighted
#' with a light yellow background.
#' @return A table object that can be piped into `lt_*()` functions.
#' @export
#' @examples
#' lt(head(mtcars[, 1:4]))
lt = function(data, ...) UseMethod('lt')

#' @rdname lt
#' @export
lt.default = function(data, auto_format = TRUE, auto_label = TRUE, ...) {
  grp = if (inherits(data, 'grouped_df'))
    setdiff(names(attr(data, 'groups')), '.rows')
  data = as.data.frame(
    data, stringsAsFactors = FALSE, check.names = FALSE, optional = TRUE
  )
  x = structure(list(data = data, ops = list()), class = 'lt_tbl')
  if (!auto_format) x$auto_format = FALSE
  if (!auto_label) x$auto_label = FALSE
  if (length(grp)) x$row_group = I(grp)
  x
}

drop_null = function(x) x[!vapply(x, is.null, logical(1))]

add_op = function(x, type, ...) {
  x$ops = c(x$ops, list(drop_null(list(type = type, ...))))
  x
}

`%||%` = function(x, y) if (is.null(x)) y else x

camel2dash = function(x) gsub('([A-Z])', '-\\L\\1', x, perl = TRUE)

# If x is a formula, extract variable names from its RHS; otherwise return as-is
f_cols = function(x) if (inherits(x, 'formula')) all.vars(x[[length(x)]]) else x
