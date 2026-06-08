#' Add a Title and Subtitle
#'
#' @inheritParams lt_align
#' @param title A character scalar.
#' @param subtitle A character scalar.
#' @return `x` with the header recorded.
#' @export
lt_header = function(x, title = NULL, subtitle = NULL) {
  x$header = drop_null(list(title = title, subtitle = subtitle))
  x
}

#' Add a Column Spanner
#'
#' A spanner is a label rendered above a contiguous group of column headers.
#'
#' When called with no `label` or `columns`, infers spanners from column
#' names by splitting on the first `.` or `_` separator. Contiguous columns
#' sharing a prefix are grouped under that prefix, and column labels are
#' shortened to the suffix.
#'
#' @inheritParams lt_align
#' @param label A character scalar — the spanner text. Alternatively, a
#'   two-sided formula `Label ~ col1 + col2` providing both the label (LHS)
#'   and columns (RHS). When missing, spanners are inferred from column names.
#' @param columns Column names (character or formula). When missing, inferred
#'   from column names.
#' @param sep Separator pattern for auto-inference (default `"[._]"`).
#' @note The columns must be contiguous in the body of the table.
#' @return `x` with the spanner recorded.
#' @export
#' @examples
#' # Explicit spanner
#' lt(head(iris)) |> lt_spanner("Sepal", c("Sepal.Length", "Sepal.Width"))
#'
#' # Auto-infer from column names
#' lt(head(iris)) |> lt_spanner()
lt_spanner = function(x, label, columns, sep = '[._]') {
  if (missing(label) && missing(columns)) {
    x$auto_span = if (identical(sep, '[._]')) TRUE else sep
    return(x)
  }
  if (inherits(label, 'formula')) {
    columns = f_cols(label)
    label = deparse(label[[2]])
  }
  columns = f_cols(columns)
  x$spanners = c(x$spanners, list(list(label = label, columns = I(as.character(columns)))))
  x
}

#' Define Row Groups
#'
#' Partition rows into labeled groups. Pass column names to group by those
#' columns' values (the columns are removed from the body and rendered as
#' rowspan cells on the left). Use `sep = TRUE` to render groups as
#' full-width separator rows instead of rowspan.
#'
#' @inheritParams lt_align
#' @param ... A column name or formula (e.g., `~col` or `~col1 + col2`) to
#'   group by column values, or named arguments of the form
#'   `"Label" = rows` (integer vector of 1-based row indices) for manual
#'   groups. Unnamed character strings reorder previously defined groups.
#' @param sep If `TRUE`, render groups as full-width separator rows instead
#'   of the default rowspan style. Only supports a single grouping column. The
#'   default `'auto'` uses separator rows when there is a single grouping
#'   column with any value longer than 20 characters.
#' @param sort If `TRUE` (default), sort rows by group columns so that
#'   identical group values are contiguous. Set to `FALSE` to preserve the
#'   original row order.
#' @return `x` with the row groups recorded.
#' @export
#' @examples
#' # Group by a column (rowspan, default)
#' d = data.frame(arm = c("Placebo", "Placebo", "Treatment", "Treatment"),
#'                stat = c("n", "Mean", "n", "Mean"), value = c(30, 4.2, 31, 6.8))
#' lt(d) |> lt_group(~ arm)
#'
#' # Separator-row style
#' lt(d) |> lt_group(~ arm, sep = TRUE)
#'
#' # Manual groups (always separator rows)
#' lt(head(mtcars)) |>
#'   lt_group("First three" = 1:3, "Last three" = 4:6)
lt_group = function(x, ..., sep = 'auto', sort = TRUE) {
  args = list(...)
  nms = names(args)
  if (!sort) x$sort = FALSE
  if (length(args) == 1 && (is.null(nms) || !nzchar(nms))) {
    col = f_cols(args[[1]])
    if (all(col %in% names(x$data))) {
      x$row_group = if (identical(sep, TRUE)) col[1] else I(col)
      return(x)
    }
  }
  if (is.null(nms) || all(!nzchar(nms))) {
    add_op(x, 'group_order', order = I(as.character(unlist(args))))
  } else {
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
#' @inheritParams lt_align
#' @param text Footnote text.
#' @param where One of `'title'`, `'subtitle'`, `'column'`, `'spanner'`,
#'   `'group'`, or `'body'`.
#' @param columns Character vector of column names or a one-sided formula (for
#'   `'column'` or `'body'`). For `'group'` with `match = "starts_with"`, a
#'   single prefix string.
#' @param rows Integer vector of 1-based row indices (for `'body'`; `NULL`
#'   means all rows).
#' @param match For `where = "group"`: one of `"exact"` (default),
#'   `"starts_with"`, or `"all"`.
#' @return `x` with the footnote recorded.
#' @export
lt_footnote = function(x, text, where, columns = NULL, rows = NULL, match = NULL) {
  columns = f_cols(columns)
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
#' @inheritParams lt_align
#' @param text Note text.
#' @return `x` with the note recorded.
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
#' @param x An [lt()] object.
#' @param columns Character vector of column names (or a one-sided formula).
#' @param align One of `"left"`, `"center"`, or `"right"`.
#' @return `x` with the alignment recorded.
#' @export
lt_align = function(x, columns, align = c('left', 'center', 'right')) {
  columns = f_cols(columns)
  align = match.arg(align)
  add_op(x, 'align', columns = I(as.character(columns)), align = align)
}

#' Format Numeric Columns
#'
#' Control the number of decimal places and thousands separator for numeric
#' columns. Columns passed to this function are excluded from automatic
#' formatting (see the `auto_fmt` argument of [lt()]). To disable auto-format
#' for a column without otherwise changing its display, call `lt_format(x,
#' ~col)` with no other arguments.
#'
#' @inheritParams lt_align
#' @param columns Character or integer vector of columns (or a one-sided
#'   formula).
#' @param decimals Number of decimal places (default `NULL` means no change).
#' @param big_mark Thousands separator (e.g., `","`). `NULL` or `""` means
#'   none.
#' @param percent If `TRUE`, multiply values by 100 and append `"%"`. If
#'   `"%"`, only append `"%"` without multiplying (for values already in
#'   percent scale).
#' @return `x` with the formatting recorded.
#' @export
lt_format = function(x, columns, decimals = NULL, big_mark = NULL, percent = NULL) {
  columns = f_cols(columns)
  cols = if (is.numeric(columns)) names(x$data)[columns] else as.character(columns)
  pct = if (identical(percent, "%")) "%" else if (isTRUE(percent)) TRUE
  add_op(x, 'fmt_number', columns = I(cols), decimals = decimals,
    big_mark = if (nzchar(big_mark %||% '')) big_mark, percent = pct)
}

#' Rename Column Labels
#'
#' Override column headers without modifying the underlying data frame.
#'
#' @inheritParams lt_align
#' @param ... Named arguments of the form `col_name = "Display Label"`.
#' @return `x` with the column label overrides recorded.
#' @export
lt_label = function(x, ...) {
  add_op(x, 'label', labels = list(...))
}


#' Substitute Cell Values
#'
#' Replace `NA`, zero, or small values with display text.
#'
#' @inheritParams lt_align
#' @param columns Character vector of column names, a one-sided formula, or
#'   `NULL` for all.
#' @param missing Replacement for `NA` cells (e.g., `"—"`). `NULL` to
#'   leave NAs as empty strings (the default rendering).
#' @param zero Replacement for zero values (e.g., `"—"`).
#' @param small Threshold: values whose absolute value is below this are
#'   replaced by `small_text`.
#' @param small_text Text shown for values below `small` (e.g., `"<0.1"`).
#' @return `x` with the substitution recorded.
#' @export
lt_sub = function(x, columns = NULL, missing = NULL, zero = NULL,
                  small = NULL, small_text = NULL) {
  columns = f_cols(columns)
  cols = if (!is.null(columns)) I(as.character(columns))
  add_op(x, 'sub', columns = cols, missing = missing, zero = zero,
    small = small, small_text = small_text)
}

#' Indent Stub Rows
#'
#' Add hierarchical indentation to row labels (stub cells). Requires that
#' the table has a stub column (see [lt_stub()]).
#'
#' @inheritParams lt_align
#' @param rows Integer vector of 1-based row indices to indent.
#' @param level Indent level (default 1). Each level adds one unit of
#'   left padding.
#' @return `x` with the indentation recorded.
#' @export
lt_indent = function(x, rows, level = 1) {
  add_op(x, 'indent', rows = I(as.integer(rows)), level = as.integer(level))
}

#' Merge Columns
#'
#' Combine values from multiple columns into a single display column using
#' a pattern. Source columns (all except the first) are hidden by default.
#'
#' @inheritParams lt_align
#' @param columns Character vector of column names (or a one-sided formula).
#'   The first column is the target (receives merged content); the rest are
#'   sources.
#' @param pattern A glue-style template using `\{1\}`, `\{2\}`, etc. to refer
#'   to columns by position. Wrap sections in `<<` and `>>` for conditional
#'   NA handling: `"\{1\}<< (\{2\})>>"` drops the wrapped portion when any
#'   referenced value is missing/empty. If `NULL`, columns are concatenated
#'   separated by spaces.
#' @param hide If `TRUE` (default), source columns (all but the first) are
#'   automatically hidden.
#' @return `x` with the merge recorded.
#' @export
lt_merge = function(x, columns, pattern = NULL, hide = TRUE) {
  columns = f_cols(columns)
  if (length(columns) < 2) stop('lt_merge() requires at least 2 columns')
  add_op(x, 'merge', columns = I(columns), pattern = pattern, hide = hide)
}

#' Style Cells
#'
#' Apply CSS styling to specific cells. Target cells by column, row, or both.
#' When `test` is provided, styles are applied conditionally based on cell
#' values (evaluated in JavaScript).
#'
#' @inheritParams lt_align
#' @param columns Character vector of column names, a one-sided formula, or
#'   `NULL` for all.
#' @param rows Integer vector of 1-based row indices (or `NULL` for all).
#' @param test A JavaScript function as a string (e.g., `"v => v < 0"`) that
#'   receives the raw cell value and returns `true` to apply the style. When
#'   `NULL`, the style applies unconditionally.
#' @param class CSS class name(s) to add to matching cells. Define the
#'   corresponding rules in an external stylesheet via [lt_css()].
#' @param bold Logical: apply bold weight?
#' @param italic Logical: apply italic style?
#' @param color Text color (any CSS color value, e.g., `"red"`, `"#06c"`).
#' @param bg Background color.
#' @param ... Additional CSS properties as named arguments. Names can be
#'   camelCase (e.g., `borderLeft`) or quoted dash-case (e.g.,
#'   `` `border-left` ``). Values are CSS strings.
#' @return `x` with the style recorded.
#' @export
#' @examples
#' lt(head(mtcars)) |>
#'   lt_style("mpg", rows = 1L, bold = TRUE, borderBottom = "2px solid red")
#' lt(head(mtcars)) |>
#'   lt_style("mpg", test = "v => v > 20", class = "high") |>
#'   lt_css(.high = list(background = "#cfc"))
lt_style = function(x, columns = NULL, rows = NULL, test = NULL, class = NULL,
                    bold = NULL, italic = NULL, color = NULL, bg = NULL, ...) {
  columns = f_cols(columns)
  css = character()
  if (isTRUE(bold))   css = c(css, 'font-weight:bold')
  if (isTRUE(italic)) css = c(css, 'font-style:italic')
  if (!is.null(color)) css = c(css, paste0('color:', color))
  if (!is.null(bg))    css = c(css, paste0('background:', bg))
  dots = list(...)
  for (nm in names(dots)) {
    css = c(css, paste0(camel2dash(nm), ':', dots[[nm]]))
  }
  css = if (length(css)) paste(css, collapse = ';')
  if (is.null(css) && is.null(class)) return(x)
  add_op(x, 'style',
    columns = if (!is.null(columns)) I(as.character(columns)),
    rows = if (!is.null(rows)) I(as.integer(rows)),
    test = if (!is.null(test)) xfun::js(test),
    class = class, css = css)
}

#' Set Column Widths
#'
#' @inheritParams lt_align
#' @param ... Named arguments of the form `col_name = "width"`. Width
#'   can be any CSS value (e.g., `"100px"`, `"20%"`, `"8em"`).
#' @return `x` with the column widths recorded.
#' @export
lt_width = function(x, ...) {
  widths = list(...)
  add_op(x, 'width', widths = widths)
}


#' Move Columns
#'
#' Rearrange column display order without modifying the data frame.
#'
#' @inheritParams lt_align
#' @param after Column name after which to place the moved columns. Use
#'   `NULL` to move to the start.
#' @return `x` with the column move recorded.
#' @export
lt_move = function(x, columns, after = NULL) {
  columns = f_cols(columns)
  add_op(x, 'move', columns = I(as.character(columns)),
    after = if (!is.null(after)) as.character(after))
}

#' Attach Custom CSS
#'
#' Add user-supplied stylesheets or inline rules that render after the
#' built-in CSS, so rules can override the defaults.
#'
#' @inheritParams lt_align
#' @param ... Unnamed arguments are stylesheet paths or URLs. A bare
#'   filename (no directory component) that does not exist in the working
#'   directory is resolved against the stylesheets shipped with lt, so
#'   e.g. `lt_css(x, "lt-gt.css")` uses the bundled gt-like theme.
#'
#'   Named arguments define inline CSS rules scoped to `.lt-table`. Names
#'   are selectors (e.g., `.na`, `td.highlight`) and values are either a
#'   CSS string or a named list of properties:
#'   `lt_css(x, .na = "background: #eee")` or
#'   `lt_css(x, .na = list(background = "#eee"))`.
#' @return `x` with the stylesheets recorded.
#' @export
#' @examples
#' \dontrun{
#' lt(head(mtcars)) |> lt_css("custom.css")
#' lt(head(mtcars)) |> lt_css("https://example.com/theme.css")
#' }
#' lt(head(mtcars)) |>
#'   lt_style("mpg", test = "v => v > 20", class = "high") |>
#'   lt_css(.high = list(background = "#cfc", fontWeight = "bold"))
lt_css = function(x, ...) {
  args = list(...)
  nms = names(args)
  named = if (!is.null(nms)) nms != ""
  if (length(named) && any(named)) {
    rules = character()
    for (i in which(named)) {
      sel = nms[i]
      val = args[[i]]
      if (is.list(val))
        val = paste0(camel2dash(names(val)), ': ', val, ';', collapse = ' ')
      rules = c(rules, sprintf('  %s { %s }', sel, val))
    }
    x$rules = c(x$rules, rules)
    args = args[!named]
  }
  paths = unlist(args, use.names = FALSE)
  if (length(paths))
    x$css = c(x$css, vapply(as.character(paths), resolve_css, character(1)))
  x
}

# A URL or an existing file is used as-is. A bare filename that is not in the
# working directory is resolved against lt's bundled stylesheets.
resolve_css = function(p) {
  if (is_url(p) || file.exists(p)) return(p)
  if (basename(p) == p) {
    f = asset_path(p)
    if (file.exists(f)) return(f)
  }
  stop("CSS file not found: ", p)
}

is_url = function(x) grepl('^(https?:)?//', x)

#' Designate a Stub Column
#'
#' Mark a column as the row-label stub. Its values become left-aligned row
#' headers and the column is removed from the table body. When row groups
#' exist and no stub is declared, the first visible column is automatically
#' promoted; use this function to override that default.
#'
#' @inheritParams lt_align
#' @param column A column name (character scalar or one-sided formula).
#' @param label Optional header label for the stub column.
#' @return `x` with the stub column recorded.
#' @export
#' @examples
#' d = data.frame(endpoint = c("OS", "PFS"), result = c("0.72", "0.58"))
#' lt(d) |> lt_stub(~ endpoint, label = "Endpoint")
lt_stub = function(x, column, label = NULL) {
  x$row_label = f_cols(column)
  if (!is.null(label)) add_op(x, 'stubhead', label = label)
  x
}
