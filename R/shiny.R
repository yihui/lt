# Shiny bindings — htmlDependency + custom output binding (no renderUI).
#
# lt_output() returns a placeholder <div class="lt-output"> plus the lt CSS,
# the lt runtime, and an output binding. render_lt() ships a `{ spec }`
# payload via shiny::markRenderFunction(); the binding receives the spec
# and calls LT.build(spec) to swap in the <table>.

lt_dependency = function() htmltools::htmlDependency(
  'lt', as.character(utils::packageVersion('lt')),
  src = system.file('www', package = 'lt'),
  stylesheet = 'lt.css',
  script = c('lt.js', 'lt-binding.js')
)

#' Shiny Output for an `lt_tbl`
#'
#' Pair with [render_lt()] to render an `lt_tbl` in a Shiny app. The UI side
#' is a `<div class="lt-output">` placeholder; an output binding swaps in
#' the rendered `<table>` whenever the server side re-evaluates the spec.
#' No `renderUI()` involved — Shiny treats the table like any other custom
#' output.
#'
#' @param outputId Output variable name to read the table from.
#' @param ... Reserved for future use.
#' @return A Shiny UI element.
#' @export
lt_output = function(outputId, ...) shiny::tagList(
  lt_dependency(),
  shiny::div(id = outputId, class = 'lt-output')
)

#' Render an `lt_tbl` in Shiny
#'
#' @param expr An expression that returns an `lt_tbl` object.
#' @param env Environment in which to evaluate `expr`.
#' @param quoted Whether `expr` is already quoted.
#' @return A render function for use with [lt_output()].
#' @export
render_lt = function(expr, env = parent.frame(), quoted = FALSE) {
  func = shiny::installExprFunction(expr, 'func', env, quoted)
  shiny::createRenderFunction(func, function(result, shinysession, name, ...) {
    if (!is.null(result)) list(spec = result)
  }, lt_output)
}
