# Re-export xfun::js so callers can mark a string as verbatim JavaScript (e.g.
# a row-detail callback for lt_interactive()) without attaching xfun. js()
# makes the spec serializer emit the string unquoted, as a real function on the
# page.

#' @importFrom xfun js
#' @export
xfun::js
