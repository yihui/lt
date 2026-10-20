#' Editable table as a Shiny input
#'
#' `lt_input()` shows an [lt()] table whose body cells can be edited in the
#' browser; the edited table is available to the server as a data frame in
#' `input[[inputId]]`. `update_lt_input()` replaces the table from the server
#' (e.g., to add or remove rows, or to reset the edits).
#'
#' Numeric columns accept only numbers (an empty cell is `NA`); other columns
#' hold text. Press `Enter` to commit a cell and move down a row. Editing does
#' not work with row groups shown as spanning cells, nor with
#' [lt_interactive()], which reorders rows.
#'
#' @param inputId The input slot that will be used to access the value.
#' @param x An [lt()] table, or a data frame.
#' @param columns Names of the editable columns; all columns by default.
#' @param session The `session` object passed to the Shiny server function.
#' @return `lt_input()` returns a Shiny UI element; `update_lt_input()` is
#'   called for its side effect.
#' @export
#' @examples
#' if (interactive()) {
#' library(shiny)
#' ui = fluidPage(lt_input("m", head(mtcars[, 1:3])), verbatimTextOutput("out"))
#' server = function(input, output) output$out = renderPrint(input$m)
#' shinyApp(ui, server)
#' }
lt_input = function(inputId, x, columns = NULL) {
  shiny::registerInputHandler('lt.table', input_data, force = TRUE)
  shiny::tagList(
    lt_dependency(plot = TRUE, input = TRUE),
    shiny::div(id = inputId, class = 'lt-input', `data-spec` = input_spec(x, columns))
  )
}

#' @rdname lt_input
#' @export
update_lt_input = function(session, inputId, x, columns = NULL)
  session$sendInputMessage(inputId, list(spec = input_spec(x, columns)))

# JSON spec of an editable table; `input` lists the editable columns
input_spec = function(x, columns = NULL) {
  if (!inherits(x, 'lt_tbl')) x = lt(x)
  if (!is.null(x$interactive)) stop('lt_interactive() tables cannot be edited')
  x$input = I(f_cols(columns, x$data) %||% names(x$data))
  xfun::tojson(lt_spec(x))
}

# Turn the column lists sent by the browser into a data frame
input_data = function(x, ...) as.data.frame(
  lapply(x, function(v) unlist(lapply(v, function(e) e %||% NA))),
  stringsAsFactors = FALSE, check.names = FALSE, optional = TRUE
)
