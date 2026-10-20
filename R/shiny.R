# Shiny bindings: htmlDependency + custom output binding (no renderUI).
#
# lt_output() returns a placeholder <div class="lt-output"> plus lt CSS, the
# runtime, and an output binding. render_lt() ships a `{ spec }` payload via
# shiny::markRenderFunction(); the binding calls LT.build(spec) to swap in the
# <table>.

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
#' @param input Whether to include the editing extension and Shiny input
#'   binding (only needed by [lt_input()]).
#' @return An `html_dependency` object.
#' @export
#' @examples
#' if (requireNamespace('htmltools', quietly = TRUE))
#'   lt_dependency(interactive = TRUE)
lt_dependency = function(
  interactive = FALSE, plot = FALSE, shiny = FALSE, input = FALSE
)
  htmltools::htmlDependency(
    'lt', as.character(utils::packageVersion('lt')),
    src = pkg_file('www'),
    stylesheet = c(
      'lt.css', if (plot) 'lt-plot.css', if (interactive) 'lt-interactive.css'
    ),
    script = c(
      if (plot) 'lt-plot.js', 'lt.js',
      if (interactive) 'lt-interactive.js', if (shiny) 'lt-binding.js',
      if (input) 'lt-input.js'
    )
  )

#' Shiny bindings for lt
#'
#' Use lt tables in Shiny apps, as outputs or as inputs.
#'
#' `lt_output()` creates a UI placeholder; `render_lt()` supplies the table
#' spec from the server. Together they render an [lt()] table as a custom
#' Shiny output — no `renderUI()` involved.
#'
#' `lt_input()` shows a table whose body cells can be edited in the browser;
#' the edited table is available to the server as a data frame in
#' `input[[inputId]]`. `lt_update()` replaces the table from the server (e.g.,
#' to add or remove rows, or to reset the edits). Numeric columns accept only
#' numbers (an empty cell is `NA`); other columns hold text. Press `Enter` to
#' commit a cell and move down a row. Editing does not work with row groups
#' shown as spanning cells, nor with [lt_interactive()], which reorders rows.
#'
#' @param outputId Output variable name to read the table from.
#' @param ... Reserved for future use.
#' @param expr An expression that returns an [lt()] object.
#' @param env Environment in which to evaluate `expr`.
#' @param quoted Whether `expr` is already quoted.
#' @param inputId The input slot that will be used to access the value.
#' @param x An [lt()] table, or a data frame (shown without automatic number
#'   formatting, so cells display the values they hold).
#' @param label Display label for the input, or `NULL` for no label.
#' @param columns Names of the editable columns; all columns by default.
#' @param session The `session` object passed to the Shiny server function.
#' @return `lt_output()` and `lt_input()` return a Shiny UI element;
#'   `render_lt()` returns a render function; `lt_update()` is called for its
#'   side effect.
#' @export
#' @examples
#' if (interactive()) {
#' library(shiny)
#' ui = fluidPage(
#'   lt_output("tbl"),
#'   lt_input("m", head(mtcars[, 1:3]), "Edit the cells:"),
#'   verbatimTextOutput("out")
#' )
#' server = function(input, output) {
#'   output$tbl = render_lt(lt(head(mtcars)) |> lt_header("Motor Trend"))
#'   output$out = renderPrint(input$m)
#' }
#' shinyApp(ui, server)
#' }
# Ship the graphics module too: render_lt()'s spec is built at render time, so
# the UI can't know whether it has a plot cell.
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
    # Wire format: list of {href} or {content} items. Absolute file paths are
    # inlined (file:// would resolve on the client, not the Shiny server).
    # URLs and relative paths ride as hrefs.
    if (length(result$css)) result$css = lapply(result$css, function(p) {
      if (is_url(p) || !xfun::is_abs_path(p)) list(href = p)
      else list(content = xfun::file_string(p))
    })
    list(spec = with_col_order(result))
  }, lt_output)
}

#' @rdname lt_output
#' @export
lt_input = function(inputId, x, label = NULL, columns = NULL) {
  shiny::registerInputHandler('lt.table', input_data, force = TRUE)
  shiny::div(
    class = 'form-group shiny-input-container',
    lt_dependency(input = TRUE),
    if (!is.null(label)) shiny::tags$label(label, `for` = inputId),
    shiny::div(id = inputId, class = 'lt-input', `data-spec` = input_spec(x, columns))
  )
}

#' @rdname lt_output
#' @export
lt_update = function(session, inputId, x, columns = NULL)
  session$sendInputMessage(inputId, list(spec = input_spec(x, columns)))

# JSON spec of an editable table; `input` lists the editable columns
input_spec = function(x, columns = NULL) {
  if (!inherits(x, 'lt_tbl')) x = lt(x, auto_format = FALSE)
  if (!is.null(x$interactive)) stop('lt_interactive() tables cannot be edited')
  x$input = I(f_cols(columns, x$data) %||% names(x$data))
  xfun::tojson(lt_spec(x))
}

# Turn the column lists sent by the browser into a data frame
input_data = function(x, ...) as.data.frame(
  lapply(x, function(v) unlist(lapply(v, function(e) e %||% NA))),
  stringsAsFactors = FALSE, check.names = FALSE, optional = TRUE
)
