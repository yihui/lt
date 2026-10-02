# Shiny bindings — htmlDependency + custom output binding (no renderUI).
#
# lt_output() returns a placeholder <div class="lt-output"> plus the lt CSS,
# the lt runtime, and an output binding. render_lt() ships a `{ spec }`
# payload via shiny::markRenderFunction(); the binding receives the spec
# and calls LT.build(spec) to swap in the <table>.

#' HTML dependency for lt tables
#'
#' The [htmltools::htmlDependency()] bundling lt's runtime assets, for embedding
#' lt tables in other HTML output (e.g. another htmlwidget or a `reactable`
#' cell) and rendering them client-side with `LT.render()` / `LT.buildHtml()`
#' on a spec from [lt_spec()]. Requires the \pkg{htmltools} package.
#'
#' @param interactive Whether to also include the interactivity extension (the
#'   assets behind [lt_interactive()]): its script and stylesheet.
#' @param plot Whether to also include the graphics module (the assets behind
#'   [lt_errorbar()] and other inline-plot cells): its script and stylesheet.
#'   Its script loads before the core runtime so plot cells render.
#' @param shiny Whether to include the Shiny output binding (only needed by
#'   [lt_output()] / [render_lt()]).
#' @return An `html_dependency` object.
#' @export
#' @examples
#' if (requireNamespace('htmltools', quietly = TRUE))
#'   lt_dependency(interactive = TRUE)
lt_dependency = function(interactive = FALSE, plot = FALSE, shiny = FALSE)
  htmltools::htmlDependency(
    'lt', as.character(utils::packageVersion('lt')),
    src = pkg_file('www'),
    stylesheet = c(
      'lt.css', if (plot) 'lt-plot.css', if (interactive) 'lt-interactive.css'
    ),
    script = c(
      if (plot) 'lt-plot.js', 'lt.js',
      if (interactive) 'lt-interactive.js', if (shiny) 'lt-binding.js'
    )
  )

#' Shiny bindings for lt
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
# Ship the graphics module too: render_lt()'s spec is produced on the server at
# render time, so the UI cannot know whether it will contain a plot cell.
lt_output = function(outputId, ...) shiny::tagList(
  lt_dependency(plot = TRUE, shiny = TRUE),
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
    list(spec = with_col_order(result))
  }, lt_output)
}
