#' View a data frame as an interactive table
#'
#' A data viewer: a shorthand for
#' `lt_interactive(lt(data, show_types = TRUE), profile = TRUE, hide = NA)`
#' with a caption made by [lt_header()]. Each column shows its type and a profile of its values, and the table can be
#' sorted, searched, filtered, paged, resized, and have columns hidden from a
#' menu. Printing the result at the console opens it in the viewer or browser.
#'
#' @param data A data frame.
#' @param title,subtitle The caption, passed to [lt_header()]. By default, the
#'   title is the expression given as `data` and the subtitle is the number of
#'   rows and columns. Use `NULL` to omit either.
#' @param profile,hide,... Arguments passed to [lt_interactive()]; `profile`
#'   defaults to `TRUE` and `hide` to `NA` (a column-visibility menu) here.
#' @return An `lt_tbl` object.
#' @export
#' @examples
#' lt_viewer(iris)
lt_viewer = function(
  data, title = deparse1(substitute(data)),
  subtitle = sprintf('%d rows, %d columns', nrow(data), ncol(data)),
  profile = TRUE, hide = NA, ...
) {
  lt(data, show_types = TRUE) |> lt_header(title, subtitle) |>
    lt_interactive(profile = profile, hide = hide, ...)
}
