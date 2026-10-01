# Re-export xfun::js so callers can mark a string as verbatim JavaScript (e.g.
# a row-detail callback for lt_interactive()) without attaching xfun. Wrapping a
# string with js() makes the spec serializer emit it unquoted, so it becomes a
# real function on the page instead of a quoted string.

#' @importFrom xfun js
#' @export
xfun::js
