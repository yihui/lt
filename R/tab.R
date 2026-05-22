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
#'   For `'group'` with `match = "starts_with"`, a single prefix string.
#' @param rows Integer vector of 1-based row indices (for `'body'`; `NULL`
#'   means all rows).
#' @param match For `where = "group"`: one of `"exact"` (default),
#'   `"starts_with"`, or `"all"`.
#' @return The `lt_tbl` with the footnote recorded.
#' @export
lt_footnote = function(x, text, where, columns = NULL, rows = NULL, match = NULL) {
  loc = switch(where,
    title = list(type = 'title', group = 'title'),
    subtitle = list(type = 'title', group = 'subtitle'),
    column = list(type = 'column_labels', columns = I(as.character(columns))),
    spanner = list(type = 'column_spanners', spanners = I(as.character(columns))),
    group = {
      m = match %||% 'exact'
      if (m == 'starts_with') {
        list(type = 'row_groups', match = 'starts_with', value = as.character(columns))
      } else if (m == 'all') {
        list(type = 'row_groups', match = 'all')
      } else {
        list(type = 'row_groups', match = 'exact', values = I(as.character(columns)))
      }
    },
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

#' Rename Column Labels
#'
#' Override column headers without modifying the underlying data frame.
#'
#' @param x An `lt_tbl` object.
#' @param ... Named arguments of the form `col_name = "Display Label"`.
#' @return The `lt_tbl` with the column label overrides recorded.
#' @export
lt_cols_label = function(x, ...) {
  add_op(x, 'cols_label', labels = list(...))
}

#' Hide Columns
#'
#' Remove columns from display without dropping them from the data. Hidden
#' columns can still be referenced by other operations (e.g., merging).
#'
#' @param x An `lt_tbl` object.
#' @param columns Character vector of column names to hide.
#' @return The `lt_tbl` with the hidden columns recorded.
#' @export
lt_hide = function(x, columns) {
  add_op(x, 'cols_hide', columns = as.character(columns))
}

#' Substitute Cell Values
#'
#' Replace `NA`, zero, or small values with display text. Runs after number
#' formatting so the substitution targets the formatted character cells.
#'
#' @param x An `lt_tbl` object.
#' @param columns Character vector of column names (or `NULL` for all).
#' @param missing Replacement for `NA` cells (e.g., `"—"`). `NULL` to
#'   leave NAs as empty strings (the default rendering).
#' @param zero Replacement for zero values (e.g., `"—"`).
#' @param small Threshold: values whose absolute value is below this are
#'   replaced by `small_text`.
#' @param small_text Text shown for values below `small` (e.g., `"<0.1"`).
#' @return The `lt_tbl` with the substitution recorded.
#' @export
lt_sub = function(x, columns = NULL, missing = NULL, zero = NULL,
                  small = NULL, small_text = NULL) {
  cols = if (!is.null(columns)) as.character(columns)
  add_op(x, 'sub', columns = cols, missing = missing, zero = zero,
    small = small, small_text = small_text)
}

#' Indent Stub Rows
#'
#' Add hierarchical indentation to row labels (stub cells). Requires that
#' the table was created with a `row_label` column via [lt()].
#'
#' @param x An `lt_tbl` object.
#' @param rows Integer vector of 1-based row indices to indent.
#' @param level Indent level (default 1). Each level adds one unit of
#'   left padding.
#' @return The `lt_tbl` with the indentation recorded.
#' @export
lt_indent = function(x, rows, level = 1) {
  add_op(x, 'indent', rows = I(as.integer(rows)), level = as.integer(level))
}

#' Merge Columns
#'
#' Combine values from multiple columns into a single display column using
#' a pattern. Source columns (all except the first) are hidden by default.
#'
#' @param x An `lt_tbl` object.
#' @param columns Character vector of column names. The first column is the
#'   target (receives merged content); the rest are sources.
#' @param pattern A glue-style template using `\{1\}`, `\{2\}`, etc. to refer
#'   to columns by position. Wrap sections in `<<` and `>>` for conditional
#'   NA handling: `"\{1\}<< (\{2\})>>"` drops the wrapped portion when any
#'   referenced value is missing/empty. If `NULL`, columns are concatenated
#'   separated by spaces.
#' @param hide If `TRUE` (default), source columns (all but the first) are
#'   automatically hidden.
#' @return The `lt_tbl` with the merge recorded.
#' @export
lt_merge = function(x, columns, pattern = NULL, hide = TRUE) {
  columns = as.character(columns)
  if (length(columns) < 2) stop('lt_merge() requires at least 2 columns')
  add_op(x, 'merge', columns = I(columns), pattern = pattern, hide = hide)
}
