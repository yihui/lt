#' View a data frame as an interactive table
#'
#' A data viewer: a shorthand for
#' `lt_interactive(lt(data, show_types = TRUE), profile = TRUE)`. Each column
#' shows its type and a profile of its values, and the table can be sorted,
#' searched, filtered, paged, and resized. Printing the result at the console
#' opens it in the viewer or browser.
#'
#' @param data A data frame.
#' @param profile,... Arguments passed to [lt_interactive()]; `profile`
#'   defaults to `TRUE` here.
#' @return An `lt_tbl` object.
#' @export
#' @examples
#' lt_viewer(iris)
lt_viewer = function(data, profile = TRUE, hide = NA, ...) lt_interactive(
  lt(data, show_types = TRUE), profile = profile, hide = hide, ...
)
