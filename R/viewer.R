#' View a data frame as an interactive table
#'
#' A data viewer: a shorthand for
#' `lt_interactive(lt(data, show_types = TRUE), profile = TRUE, hide = NA)`
#' with the data expression as the title, made by [lt_header()]. Each column
#' shows its type and a profile of its values, and the table can be sorted,
#' searched, filtered, paged, resized, and have columns hidden from a menu.
#' Printing the result at the console opens it in the viewer or browser. Use
#' `|> lt_header(NULL)` to remove the title.
#'
#' @param data A data frame.
#' @param profile,hide,... Arguments passed to [lt_interactive()]; `profile`
#'   defaults to `TRUE` and `hide` to `NA` (a column-visibility menu) here.
#' @return An `lt_tbl` object.
#' @export
#' @examples
#' lt_viewer(iris)
#' lt_viewer(iris) |> lt_header(NULL)
lt_viewer = function(data, profile = TRUE, hide = NA, ...) {
  title = deparse1(substitute(data))
  lt(data, show_types = TRUE) |> lt_header(title) |>
    lt_interactive(profile = profile, hide = hide, ...)
}
