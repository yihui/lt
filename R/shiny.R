# Shiny bindings — htmlDependency + custom output binding (no renderUI).
#
# lt_output() returns a placeholder <div class="lt-output"> plus the lt CSS,
# the lt runtime, and an output binding. render_lt() ships a `{ spec }`
# payload via shiny::markRenderFunction(); the binding receives the spec
# and calls LT.build(spec) to swap in the <table>.

lt_dependency = function() htmltools::htmlDependency(
  'lt', as.character(utils::packageVersion('lt')),
  src = pkg_file('www'),
  stylesheet = 'lt.css',
  script = c('lt.js', 'lt-binding.js')
)

#' Shiny Bindings for lt
#'
#' `lt_output()` creates a UI placeholder; `render_lt()` supplies the table
#' spec from the server. Together they render an [lt()] table as a custom
#' Shiny output — no `renderUI()` involved.
#'
#' @param outputId Output variable name to read the table from.
#' @param ... Reserved for future use.
#' @param expr An expression that returns an [lt()] object.
#' @param env Environment in which to evaluate `expr`.
#' @param quoted Whether `expr` is already quoted.
#' @return `lt_output()` returns a Shiny UI element; `render_lt()` returns a
#'   render function.
#' @export
#' @examples
#' if (interactive()) {
#' library(shiny)
#' ui = fluidPage(lt_output("tbl"))
#' server = function(input, output) {
#'   output$tbl = render_lt(lt(head(mtcars)) |> lt_header("Motor Trend"))
#' }
#' shinyApp(ui, server)
#' }
lt_output = function(outputId, ...) shiny::tagList(
  lt_dependency(),
  shiny::div(id = outputId, class = 'lt-output')
)

#' @rdname lt_output
#' @export
render_lt = function(expr, env = parent.frame(), quoted = FALSE) {
  func = shiny::installExprFunction(expr, 'func', env, quoted)
  shiny::createRenderFunction(func, function(result, shinysession, name, ...) {
    if (is.null(result)) return(NULL)
    # Wire format: list of {href} or {content} items. Absolute file paths
    # are inlined — file:// would resolve against the client's filesystem,
    # not the Shiny server. URLs and relative paths ride as hrefs.
    if (length(result$css)) result$css = lapply(result$css, function(p) {
      if (is_url(p) || !xfun::is_abs_path(p)) list(href = p)
      else list(content = xfun::file_string(p))
    })
    list(spec = result)
  }, lt_output)
}
