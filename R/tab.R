#' Add a Title and Subtitle
#'
#' @param x An `lt_tbl` object.
#' @param title A character scalar.
#' @param subtitle A character scalar.
#' @return The `lt_tbl` with the header recorded.
#' @export
lt_header = function(x, title = NULL, subtitle = NULL) {
  add_op(x, 'header', title = title, subtitle = subtitle)
}

#' Add a Column Spanner
#'
#' A spanner is a label rendered above a contiguous group of column headers.
#'
#' @param x An `lt_tbl` object.
#' @param label A character scalar — the spanner text.
#' @param columns A character vector of column names that the spanner covers.
#'   The columns must be contiguous in the body of the table.
#' @return The `lt_tbl` with the spanner recorded.
#' @export
lt_spanner = function(x, label, columns) {
  add_op(x, 'spanner', label = label, columns = I(as.character(columns)))
}

#' Add a Manual Row Group
#'
#' Most tables get row groups via `lt(data, row_group = "Analysis")`. Use
#' `lt_group()` only when you need to override or rename auto-detected
#' groups.
#'
#' @param x An `lt_tbl` object.
#' @param label Group label.
#' @param rows Integer vector of row indices belonging to this group.
#' @return The `lt_tbl` with the row group recorded.
#' @export
lt_group = function(x, label, rows) {
  add_op(x, 'row_group', label = label, rows = I(as.integer(rows)))
}

#' Add a Footnote
#'
#' Attaches a footnote `text` to a table region. Footnotes are numbered
#' automatically in the order they are added (de-duplicated by text).
#'
#' @param x An `lt_tbl` object.
#' @param text Footnote text.
#' @param where One of `'title'`, `'subtitle'`, `'column'`, `'spanner'`,
#'   `'group'`, or `'body'`.
#' @param columns Character vector of column names (for `'column'` or `'body'`).
#' @param rows Integer vector of 1-based row indices (for `'body'`; `NULL`
#'   means all rows).
#' @return The `lt_tbl` with the footnote recorded.
#' @export
lt_footnote = function(x, text, where, columns = NULL, rows = NULL) {
  loc = switch(where,
    title = list(type = 'title', group = 'title'),
    subtitle = list(type = 'title', group = 'subtitle'),
    column = list(type = 'column_labels', columns = I(as.character(columns))),
    spanner = list(type = 'column_spanners', spanners = I(as.character(columns))),
    group = list(type = 'row_groups', match = 'exact', values = I(as.character(columns))),
    body = list(type = 'body', columns = I(as.character(columns)),
      rows = if (is.null(rows)) NULL else I(as.integer(rows))),
    stop("'where' must be one of: title, subtitle, column, spanner, group, body")
  )
  add_op(x, 'footnote', text = text, location = loc)
}

#' Add a Note
#'
#' Notes are rendered in the table footer below numbered footnotes.
#'
#' @param x An `lt_tbl` object.
#' @param text Note text.
#' @return The `lt_tbl` with the note recorded.
#' @export
lt_note = function(x, text) {
  add_op(x, 'note', text = text)
}

#' Set Column Alignment
#'
#' Override the auto-detected alignment for specific columns. By default,
#' numeric columns are right-aligned and character columns are left-aligned.
#'
#' @param x An `lt_tbl` object.
#' @param columns Character vector of column names.
#' @param align One of `"left"`, `"center"`, or `"right"`.
#' @return The `lt_tbl` with the alignment recorded.
#' @export
lt_align = function(x, columns, align = c('left', 'center', 'right')) {
  align = match.arg(align)
  add_op(x, 'align', columns = as.character(columns), align = align)
}

#' Format Numeric Columns
#'
#' Applies `formatC(..., format = 'f', digits = decimals, big.mark = big_mark)`
#' to the named columns. The formatting is done in R so the rendered HTML
#' carries the formatted strings — the JS layer never re-parses numbers.
#'
#' @param x An `lt_tbl` object.
#' @param columns Character or integer vector of columns.
#' @param decimals Integer scalar.
#' @param big_mark Character scalar.
#' @return The `lt_tbl` with the formatting recorded.
#' @export
lt_format = function(x, columns, decimals = 2, big_mark = '') {
  cols = if (is.numeric(columns)) names(x$data)[columns] else as.character(columns)
  add_op(x, 'fmt_number', columns = cols, decimals = decimals, big_mark = big_mark)
}
