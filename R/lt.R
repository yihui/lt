#' lt: Lightweight Tables via JSON Specs and JavaScript
#'
#' A small grammar of tables. A table is a data frame plus a list of
#' operations (title, spanner, footnote, ...); the operations are serialised to
#' a JSON spec and applied to a plain semantic HTML table by a tiny vanilla
#' JavaScript runtime at render time.
#'
#' @name lt-package
#' @keywords internal
'_PACKAGE'

#' Create a Table Specification
#'
#' Entry point of the lightweight grammar of tables. Returns an `lt_tbl`
#' object (a list) that records the data plus a list of table-modifying
#' operations. The object is rendered to HTML by [format()] (called
#' automatically by the print method).
#'
#' @param data A data frame (or anything coercible to one).
#' @param row_group Name of a column whose values should become row-group
#'   labels. The column is removed from the body. Mirrors
#'   `dplyr::group_by()` + `gt::gt()`.
#' @param row_label Name of a column whose values become row labels (the
#'   "stub", left-aligned, no header). `NULL` means no stub.
#' @return An object of class `lt_tbl`.
#' @export
#' @examples
#' lt(head(mtcars[, 1:4]))
lt = function(data, row_group = NULL, row_label = NULL) {
  data = as.data.frame(
    data, stringsAsFactors = FALSE, check.names = FALSE, optional = TRUE
  )
  if (!is.null(row_group) && !row_group %in% names(data))
    stop("row_group '", row_group, "' is not a column of data")
  if (!is.null(row_label) && !row_label %in% names(data))
    stop("row_label '", row_label, "' is not a column of data")
  structure(
    list(
      data = data,
      row_group = row_group,
      row_label = row_label,
      ops = list()
    ),
    class = 'lt_tbl'
  )
}

# Append one operation to an lt_tbl. Each op is a list with a `type` and the
# arguments needed to render it. Ops are data, not closures, so the whole
# spec can be JSON-serialised.
add_op = function(x, type, ...) {
  x$ops = c(x$ops, list(list(type = type, ...)))
  x
}

`%||%` = function(x, y) if (is.null(x)) y else x
