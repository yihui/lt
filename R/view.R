#' View a data frame as an interactive table in a browser or editor
#'
#' Convert a data frame to an [lt()] table, enable [lt_interactive()] controls,
#' and open a local HTTP preview in the default browser. An existing
#' `lt_tbl` keeps its formatting and other table operations. Its existing
#' interactive settings are kept when `...` is empty and `filter` is not
#' supplied; otherwise these arguments configure the controls. Browser zoom
#' can be used to change the displayed font size.
#'
#' Use `open = FALSE` to print and return the preview URL for an editor,
#' integrated browser, or AI tool. The preview serves only the generated table
#' and is available while the R session remains open. Tools running on another
#' computer need access to the local port, for example through port forwarding.
#' Reusing `name` replaces that preview; [xfun::stop_app()] stops it.
#'
#' @param data A data frame or an existing `lt_tbl`.
#' @param ... Arguments passed to [lt_interactive()], such as `pager`,
#'   `resize`, and `hide`.
#' @param filter Per-column filters, passed to [lt_interactive()]. Defaults
#'   to `TRUE` to show a filter under each column. Use `FALSE` to disable them.
#' @param file An HTML output path. By default, a temporary file is used;
#'   supply a path to keep the page.
#' @param browser A browser command or function passed to [utils::browseURL()].
#'   Defaults to the browser configured by R. A function receives the preview
#'   URL (or the file path when `serve = FALSE`).
#' @param open Whether to open the preview using `browser`. If `FALSE`, its
#'   address is printed instead.
#' @param serve Whether to serve the table over local HTTP. Use `FALSE` to
#'   open the HTML file directly instead.
#' @param name A name for the local preview, passed to [xfun::new_app()].
#' @param wait Whether to keep serving until interrupted. Defaults to `TRUE`
#'   for HTTP previews in non-interactive sessions, so an `Rscript` command
#'   keeps the URL available. Interactive R sessions return immediately.
#' @return The local preview URL, or the absolute HTML file path when
#'   `serve = FALSE`, invisibly.
#' @export
#' @examples
#' # Opens the browser when run interactively:
#' if (interactive()) view_lt(mtcars, pager = FALSE)
#' # Print a URL that an editor or AI tool can open:
#' if (interactive()) url = view_lt(mtcars, open = FALSE)
view_lt = function(
  data, ..., filter = TRUE, file = tempfile('lt-view-', fileext = '.html'),
  browser = getOption('browser'), open = TRUE, serve = TRUE, name = 'lt-view',
  wait = serve && !interactive()
) {
  if (!is.character(file) || length(file) != 1L || is.na(file) ||
      !grepl('\\.html$', file, ignore.case = TRUE))
    stop('`file` must be a single .html path.')
  x = if (inherits(data, 'lt_tbl')) data else lt(data)
  if (is.null(x$interactive) || ...length() || !missing(filter))
    x = lt_interactive(x, ..., filter = filter)
  lt_export(x, file, method = 'raw')
  address = normalizePath(file, mustWork = TRUE)
  if (serve) {
    html = paste(xfun::read_utf8(file), collapse = '\n')
    address = xfun::new_app(name, function(...) list(
      payload = html, 'content-type' = 'text/html'
    ), open = FALSE)
  }
  if (open) utils::browseURL(address, browser = browser)
  else message('lt table: ', address)
  if (serve && wait) {
    on.exit(xfun::stop_app(name), add = TRUE)
    tryCatch(while (TRUE) Sys.sleep(1), interrupt = function(e) invisible(NULL))
  }
  invisible(address)
}
