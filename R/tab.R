#' Add a Title and Subtitle
#'
#' @param x An `lt_tbl` object.
#' @param title A character scalar.
#' @param subtitle A character scalar.
#' @return The `lt_tbl` with the header recorded.
#' @export
lt_header = function(x, title = NULL, subtitle = NULL) {
  x$header = drop_null(list(title = title, subtitle = subtitle))
  x
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
  x$spanners = c(x$spanners, list(list(label = label, columns = I(as.character(columns)))))
  x
}

#' Define or Reorder Row Groups
#'
#' Define manual row groups, or reorder auto-detected groups (from
#' `lt(data, row_group = "col")`). The display order matches argument order.
#'
#' @param x An `lt_tbl` object.
#' @param ... Either named arguments of the form `"Label" = rows` (integer
#'   vector of 1-based row indices) to define manual groups, or unnamed
#'   character strings to reorder auto-detected groups.
#' @return The `lt_tbl` with the row groups recorded.
#' @export
#' @examples
#' # Manual groups
#' lt(head(mtcars[, 1:4])) |>
#'   lt_group("First three" = 1:3, "Last three" = 4:6)
#'
#' # Reorder auto-detected groups
#' d = data.frame(arm = c("Placebo", "Placebo", "Treatment", "Treatment"),
#'                stat = c("n", "Mean", "n", "Mean"), value = c(30, 4.2, 31, 6.8))
#' lt(d, row_group = "arm") |> lt_group("Treatment", "Placebo")
lt_group = function(x, ...) {
  args = list(...)
  nms = names(args)
  if (is.null(nms) || all(!nzchar(nms))) {
    # Unnamed strings: reorder auto-detected groups
    add_op(x, 'group_order', order = I(as.character(unlist(args))))
  } else {
    # Named arguments: define manual groups
    for (i in seq_along(args))
      x = add_op(x, 'row_group', label = nms[i], rows = I(as.integer(args[[i]])))
    x
  }
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
  x$footnotes = c(x$footnotes, list(list(text = text, location = loc)))
  x
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
  x$notes = c(x$notes, list(text))
  x
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
#' Control the number of decimal places and thousands separator for numeric
#' columns.
#'
#' @param x An `lt_tbl` object.
#' @param columns Character or integer vector of columns.
#' @param decimals Number of decimal places (default `NULL` means no change).
#' @param big_mark Thousands separator (e.g., `","`). `NULL` or `""` means
#'   none.
#' @return The `lt_tbl` with the formatting recorded.
#' @export
lt_format = function(x, columns, decimals = NULL, big_mark = NULL) {
  cols = if (is.numeric(columns)) names(x$data)[columns] else as.character(columns)
  add_op(x, 'fmt_number', columns = cols, decimals = decimals,
    big_mark = if (nzchar(big_mark %||% '')) big_mark)
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


#' Substitute Cell Values
#'
#' Replace `NA`, zero, or small values with display text.
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

#' Style Cells
#'
#' Apply CSS styling to specific cells. Target cells by column, row, or both.
#'
#' @param x An `lt_tbl` object.
#' @param columns Character vector of column names (or `NULL` for all).
#' @param rows Integer vector of 1-based row indices (or `NULL` for all).
#' @param bold Logical: apply bold weight?
#' @param italic Logical: apply italic style?
#' @param color Text color (any CSS color value, e.g., `"red"`, `"#06c"`).
#' @param bg Background color.
#' @param ... Additional CSS properties as named arguments. Names can be
#'   camelCase (e.g., `borderLeft`) or quoted dash-case (e.g.,
#'   `` `border-left` ``). Values are CSS strings.
#' @return The `lt_tbl` with the style recorded.
#' @export
#' @examples
#' lt(head(mtcars[, 1:3])) |>
#'   lt_style("mpg", rows = 1L, bold = TRUE, borderBottom = "2px solid red")
lt_style = function(x, columns = NULL, rows = NULL, bold = NULL, italic = NULL,
                    color = NULL, bg = NULL, ...) {
  css = character()
  if (isTRUE(bold))   css = c(css, 'font-weight:bold')
  if (isTRUE(italic)) css = c(css, 'font-style:italic')
  if (!is.null(color)) css = c(css, paste0('color:', color))
  if (!is.null(bg))    css = c(css, paste0('background:', bg))
  dots = list(...)
  for (nm in names(dots)) {
    prop = gsub('([A-Z])', '-\\L\\1', nm, perl = TRUE)
    css = c(css, paste0(prop, ':', dots[[nm]]))
  }
  if (!length(css)) return(x)
  add_op(x, 'style',
    columns = if (!is.null(columns)) as.character(columns),
    rows = if (!is.null(rows)) I(as.integer(rows)),
    css = paste(css, collapse = ';'))
}

#' Set Column Widths
#'
#' @param x An `lt_tbl` object.
#' @param ... Named arguments of the form `col_name = "width"`. Width
#'   can be any CSS value (e.g., `"100px"`, `"20%"`, `"8em"`).
#' @return The `lt_tbl` with the column widths recorded.
#' @export
lt_cols_width = function(x, ...) {
  widths = list(...)
  add_op(x, 'cols_width', widths = widths)
}


#' Move Columns
#'
#' Rearrange column display order without modifying the data frame.
#'
#' @param x An `lt_tbl` object.
#' @param columns Character vector of column names to move.
#' @param after Column name after which to place the moved columns. Use
#'   `NULL` to move to the start.
#' @return The `lt_tbl` with the column move recorded.
#' @export
lt_cols_move = function(x, columns, after = NULL) {
  add_op(x, 'cols_move', columns = as.character(columns),
    after = if (!is.null(after)) as.character(after))
}

#' Set Stubhead Label
#'
#' Override the column header for the stub (row label) column.
#'
#' @param x An `lt_tbl` object.
#' @param label Character scalar for the stub column header.
#' @return The `lt_tbl` with the stubhead label recorded.
#' @export
lt_stubhead = function(x, label) {
  add_op(x, 'stubhead', label = label)
}
