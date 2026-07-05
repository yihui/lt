# Rendering: turn an lt_tbl into HTML.
#
# Strategy: emit a <script> block that pushes a JSON spec (raw data +
# declarative ops) onto LT.q. The JS runtime (lt.js) applies ops
# (format, sub, merge, etc.) to the raw data and renders the <table>.
# One runtime per page renders any number of tables.

pkg_file = function(...) {
  system.file(..., package = 'lt', mustWork = TRUE)
}

asset_path = function(file) {
  p = system.file('www', file, package = 'lt')
  if (!nzchar(p)) p = file.path('inst', 'www', file)
  p
}

read_asset = function(file) {
  p = asset_path(file)
  if (!file.exists(p)) stop('asset not found: ', file, ' (looked at ', p, ')')
  xfun::read_utf8(p)
}

asset_url = function(file) {
  url = getOption('lt.assets_url')
  if (!is.null(url)) return(paste0(url, file))
  if (isTRUE(getOption('lt.local'))) return(paste0('file://', asset_path(file)))
  sub = if (grepl('\\.js$', file)) 'js' else 'css'
  sprintf(
    'https://cdn.jsdelivr.net/npm/@xiee/utils@%s/%s/%s',
    read.dcf(pkg_file('DESCRIPTION'))[, 'Config/lt.js'],
    sub, sub('\\.(js|css)$', '.min.\\1', file)
  )
}

# Anything inlined inside a <script>...</script> wrapper must not contain
# the literal sequence `</script` (case-insensitive) — the HTML parser
# would end the script there. `<\/script` is harmless inside JS strings,
# JSON, and comments. We do NOT touch other `</tag>` sequences: rewriting
# them inside a JS regex literal (e.g. `/</g`) would break the regex.
# lt.js itself uses `[<]` instead of `<` in its only HTML-escape regex
# specifically so this minimal escape is sufficient.
inline_safe = function(s) gsub(
  '</(script)', '<\\\\/\\1', s, perl = TRUE, ignore.case = TRUE
)

# Inline CSS + JS runtime. Emit once per page; the runtime is idempotent if
# included twice, but the bytes are wasteful — pass `inline = FALSE` for
# the linked form (litedown dedups identical <link>/<script src> tags).
css_block = function(inline = TRUE) {
  if (inline) c('<style>', read_asset('lt.css'), '</style>')
  else sprintf('<link rel="stylesheet" href="%s">', asset_url('lt.css'))
}

# User CSS path -> tag. URLs and relative paths become <link> (browser
# dedups identical hrefs). Absolute paths are inlined as <style> by default
# because file:// URLs only resolve on the client's local filesystem — which
# breaks RStudio Server, Shiny Server, and any remote-render scenario. The
# `local` flag opts into file:// for the record_print path, where litedown
# inlines such files at document-assembly time.
user_css_tag = function(p, local = FALSE) {
  if (is_url(p) || !xfun::is_abs_path(p))
    sprintf('<link rel="stylesheet" href="%s">', p)
  else if (local)
    sprintf('<link rel="stylesheet" href="file://%s">', p)
  else
    c('<style>', xfun::read_utf8(p), '</style>')
}

user_css_block = function(paths, local = FALSE) {
  unlist(lapply(paths, user_css_tag, local = local))
}

rules_block = function(rules) {
  if (length(rules)) c('<style>.lt-table {', rules, '}</style>')
}

js_block = function(inline = TRUE) {
  if (inline) c('<script>', inline_safe(read_asset('lt.js')), '</script>')
  else sprintf('<script src="%s" defer></script>', asset_url('lt.js'))
}

# Per-table block: queue the spec with a reference to the current script.
# The runtime drains the queue when it loads.
spec_block = function(x) {
  # Drop css from the static-path spec (already emitted as <link>/<style>);
  # for the Shiny path we keep it on the wire so the output binding can inject links.
  x$css = x$rules = NULL
  c(
    '<script>((window.LT=window.LT||{}).q=window.LT.q||[]).push({s:document.currentScript,d:',
    inline_safe(xfun::tojson(x[lengths(x) > 0L])),
    '})</script>'
  )
}

html_doc = function(body) c(
  '<!DOCTYPE html><html><head><meta charset="utf-8"><title>lt</title>',
  '<style>body{font-family:system-ui,sans-serif;padding:1em}</style></head>',
  '<body>', body, '</body></html>'
)

#' Render an `lt_tbl` to HTML
#'
#' Emits the CSS+JS runtime and a script block carrying the table's JSON spec.
#' Multiple tables on the same page only need the runtime once.
#'
#' @param x An `lt_tbl` object.
#' @param fragment If `TRUE` (default), return an HTML fragment suitable for
#'   embedding. If `FALSE`, wrap in a minimal `<html><body>` document.
#' @param inline_assets If `TRUE` (default), inline the CSS/JS as text. If
#'   `FALSE`, emit `<link>` / `<script src=...>` tags (assets must be served
#'   alongside the HTML).
#' @param assets Which runtime assets to include: `TRUE` (default) for both
#'   CSS and JS, `FALSE` for neither, or a character vector subset of
#'   `c("css", "js")` for selective inclusion.
#' @param ... Reserved for future use.
#' @return A character scalar containing HTML.
#' @export
#' @examples
#' tbl = lt(head(mtcars))
#' html = format(tbl)
#' format(tbl, fragment = FALSE, inline_assets = FALSE)
format.lt_tbl = function(x, fragment = TRUE, inline_assets = TRUE, assets = TRUE, ...) {
  if (isTRUE(assets)) assets = c('css', 'js')
  if (isFALSE(assets)) assets = character()
  body = c(
    if ('css' %in% assets) css_block(inline_assets),
    user_css_block(x$css),
    rules_block(x$rules),
    spec_block(x),
    if ('js' %in% assets) js_block(inline_assets)
  )
  if (!fragment) body = html_doc(body)
  paste(body, collapse = '\n')
}

#' Print an `lt_tbl` (Opens in the Viewer or Browser)
#'
#' @param x An `lt_tbl` object.
#' @param ... Passed to [format()].
#' @return `x`, invisibly.
#' @export
#' @examples
#' print(lt(head(mtcars)))
print.lt_tbl = function(x, ...) {
  xfun::html_view(format(x, fragment = FALSE, ...), name = 'lt')
  invisible(x)
}

# knit_print: dedup the CSS+JS runtime within a document via opts_knit
# (per-document, auto-resets between knits). knitr is loaded when
# knit_print fires, so this never reaches knitr:: when knitr is absent.
.knit_flag = 'lt.assets_added'
.css_flag = 'lt.css_added'

knit_print.lt_tbl = function(x, ...) {
  if (is.list(opts <- getOption('lt.lt_html'))) return(structure(
    do.call(lt_html, c(list(x), opts)), class = 'knit_asis'
  ))
  first = !isTRUE(knitr::opts_knit$get(.knit_flag))
  if (first) knitr::opts_knit$set(stats::setNames(list(TRUE), .knit_flag))
  # Dedup user CSS (from lt_css()) across the document: a stylesheet shared
  # by many tables (e.g. a package theme) should be emitted once. Identical
  # <link> hrefs would dedup in the browser, but inlined <style> blocks
  # (absolute paths) would not — so filter against what's already emitted.
  seen = knitr::opts_knit$get(.css_flag)
  x$css = setdiff(x$css, seen)
  if (length(x$css))
    knitr::opts_knit$set(stats::setNames(list(c(seen, x$css)), .css_flag))
  structure(format(x, assets = first), class = c('knit_asis', 'html'))
}

# record_print (litedown / xfun::record): for HTML output emit assets + spec;
# for non-HTML output (markdown), render to static HTML via lt_html().

#' @importFrom xfun record_print
#' @export
record_print.lt_tbl = function(x, ...) {
  if (is.list(opts <- getOption('lt.lt_html')))
    return(xfun::new_record(c(do.call(lt_html, c(list(x), opts)), ''), 'asis'))
  xfun::new_record(c(
    css_block(inline = FALSE), user_css_block(x$css, local = TRUE),
    rules_block(x$rules), spec_block(x), js_block(inline = FALSE), ''
  ), 'asis')
}

# Each Jupyter cell is rendered as a sandboxed document, so we always emit
# a complete page with assets — no cross-cell dedup possible.
repr_html.lt_tbl = function(obj, ...) format(obj, fragment = FALSE)

repr_text.lt_tbl = function(obj, ...) {
  sprintf('lt_tbl (%d rows x %d cols)', nrow(obj$data), ncol(obj$data))
}

# Register S3 methods for knitr / repr (Jupyter) without hard dependencies:
# wire the methods at .onLoad.
register_s3 = function(pkgs, generics) {
  for (i in seq_along(pkgs)) local({
    pkg = pkgs[[i]]; generic = generics[[i]]
    hook = function(...) registerS3method(
      generic, 'lt_tbl',
      asNamespace('lt')[[paste0(generic, '.lt_tbl')]],
      envir = asNamespace(pkg)
    )
    if (isNamespaceLoaded(pkg)) hook()
    setHook(packageEvent(pkg, 'onLoad'), hook)
  })
}


#' Render an lt table to a static HTML table
#'
#' Execute the JavaScript runtime to produce a rendered `<table>` element. Two
#' methods are available: `"node"` uses Node.js; `"browser"` uses a headless
#' Chromium browser (via [xfun::browser_dom()]). The default `"auto"` tries
#' Node first (faster), then falls back to the browser.
#'
#' @param x An `lt_tbl` object.
#' @param method One of `"auto"`, `"browser"`, or `"node"`.
#' @param css Whether to include the lt.css runtime stylesheet in the output.
#'   User CSS from [lt_css()] is always included.
#' @param fragment If `FALSE` (default), wrap in a full HTML document. If
#'   `TRUE`, return only the rendered fragment.
#' @return A character vector of the rendered HTML.
#' @section Global option:
#' When the option `lt.lt_html` is set to a list of arguments (e.g.,
#' `options(lt.lt_html = list(fragment = TRUE, css = FALSE))`), the
#' [knit_print][knitr::knit_print] and [record_print][xfun::record_print]
#' methods will call `lt_html()` with these arguments instead of emitting the
#' default JavaScript-based spec. This is useful for output formats that
#' support raw HTML but cannot run JavaScript (e.g., GitHub Flavored
#' Markdown).
#' @export
#' @examples
#' if (interactive()) lt_html(lt(head(mtcars)))
lt_html = function(
  x, method = c('auto', 'node', 'browser'), css = TRUE, fragment = FALSE
) {
  method = match.arg(method)
  if (method == 'auto') method = if (has_node()) 'node' else if (has_browser()) 'browser'
  if (is.null(method)) stop(
    'No rendering method available. Install a Chromium-based browser or Node.js.'
  )
  html = switch(method, browser = lt_html_browser(x, css), node = lt_html_node(x, css))
  if (!fragment) html = html_doc(html)
  xfun::raw_string(html)
}

lt_html_browser = function(x, css = TRUE) {
  f = tempfile(fileext = '.html')
  on.exit(unlink(f), add = TRUE)
  xfun::write_utf8(format(x, fragment = FALSE, assets = c(if (css) 'css', 'js')), f)
  xfun::browser_dom(f, fragment = TRUE)
}

lt_html_node = function(x, css = TRUE) {
  js = pkg_file('www', 'lt.js')
  runner = pkg_file('js', 'run-lt.js')
  spec = x; spec$css = spec$rules = NULL
  if (!length(spec$ops)) spec$ops = NULL
  json = xfun::tojson(spec)
  out = system2('node', c(shQuote(runner), shQuote(js)), input = json, stdout = TRUE)
  if (!is.null(attr(out, 'status'))) stop('Node.js failed to render the lt table.')
  Encoding(out) = 'UTF-8'
  c(if (css) css_block(TRUE), user_css_block(x$css), rules_block(x$rules), out)
}

# Write `html` to a temp file, run it through headless Chromium via
# `fun`, and clean up. Shared by the measure pass (browser_dom) and the
# render pass (browser_print).
with_temp_html = function(html, fun) {
  f = tempfile(fileext = '.html')
  on.exit(unlink(f), add = TRUE)
  xfun::write_utf8(html, f)
  fun(f)
}

# Layout CSS shared by the measure and render passes: zero the page margins
# so the table sits flush at the top-left, add the crop padding, and set the
# body width. Both passes MUST use identical layout so the size measured in
# pass 1 matches what pass 2 renders. `pad` is c(vertical, horizontal) in CSS
# pixels; `width` is the outer body width in pixels (NULL = shrink to the
# table's natural width). box-sizing keeps `padding` inside `width`.
crop_layout = function(pad, width = NULL) sprintf(paste0(
  'html,body{margin:0!important}',
  'body{box-sizing:border-box;padding:%dpx %dpx!important;width:%s}'
), pad[1L], pad[2L], if (is.null(width)) 'max-content' else paste0(width, 'px'))

# Measure the rendered table's full pixel size (including the crop padding).
# Chromium runs lt.js, so the box is only known after the JS builds the
# table; inject a load handler that stamps body.scrollWidth/scrollHeight onto
# <body> as data attributes, dump the DOM, and parse them back. We measure
# the body's scroll size rather than the table's bounding box because parts
# of the table (caption border, footer spacing) extend beyond the table's
# own border-box; using the table box alone undercounts the height and makes
# the PDF spill onto a second page. Returns integer c(width, height).
lt_measure = function(html, pad, width = NULL, browser = NULL) {
  inject = paste0(
    '<style>', crop_layout(pad, width), '</style>',
    '<script>addEventListener("load",function(){',
    'var b=document.body;',
    'b.dataset.ltw=b.scrollWidth;b.dataset.lth=b.scrollHeight})</script>'
  )
  html = sub('</head>', paste0(inject, '</head>'), html, fixed = TRUE)
  dom = with_temp_html(html, function(f) xfun::browser_dom(f, browser = browser))
  m = regmatches(dom, regexec('data-ltw="([0-9]+)" data-lth="([0-9]+)"', dom))[[1]]
  if (length(m) != 3L) stop('Failed to measure the table dimensions.')
  as.integer(m[-1L])
}

#' Export an lt table to a file
#'
#' Save a table to disk. The output format is chosen from the file extension
#' of `output`: `.html` writes a static HTML table (via [lt_html()], no
#' JavaScript needed to view it), `.pdf` writes a vector PDF, and any other
#' extension writes a PNG. PDF and PNG are produced by rendering the table in
#' a headless Chromium browser (via [xfun::browser_print()]).
#'
#' @param x An `lt_tbl` object.
#' @param output Output file path. Its extension selects the format: `.html`,
#'   `.pdf`, or (otherwise) PNG.
#' @param crop Whether to crop the PDF/PNG tightly to the table, removing the
#'   surrounding page whitespace. This adds a preliminary browser pass to
#'   measure the rendered table. Set to `FALSE` for the default full page.
#'   Cropping PNG output requires the \pkg{magick} package; without it, PNG
#'   falls back to the full page (with a warning). Ignored for `.html`.
#' @param width,height The width and height of the table in CSS pixels. By
#'   default (`NULL`) the width shrinks to the table's natural width and the
#'   height is measured; specify either to override. Setting `width` smaller
#'   than the natural width wraps cell content; a larger `width` pads the
#'   table. Ignored for `.html`.
#' @param padding Padding in CSS pixels to keep around the table when
#'   cropping. A single value (all sides) or a length-two vector
#'   `c(vertical, horizontal)`.
#' @param browser Path to the Chromium-based browser; passed to
#'   [xfun::browser_print()]. `NULL` (default) auto-detects.
#' @param ... For PDF/PNG, passed to [xfun::browser_print()]; for `.html`,
#'   passed to [lt_html()].
#' @return The `output` path.
#' @export
#' @examples
#' if (interactive()) lt_export(lt(head(mtcars)), 'mtcars.png')
lt_export = function(
  x, output = 'lt.pdf', crop = TRUE, width = NULL, height = NULL,
  padding = 8, browser = NULL, ...
) {
  ext = tolower(xfun::file_ext(output))
  # .html: a static table needs no browser; delegate to the HTML exporter.
  if (ext == 'html') {
    xfun::write_utf8(lt_html(x, ...), output)
    return(output)
  }
  html = format(x, fragment = FALSE)
  is_pdf = ext == 'pdf'
  # PNG cropping needs magick to trim Chromium's screenshot (its --screenshot
  # size is the window size, which we can't shrink below Chromium's minimums).
  # PDF cropping needs no extra package: an @page rule sets the page box.
  if (crop && !is_pdf && !xfun::loadable('magick')) {
    warning('Cropping PNG output requires the magick package; ',
            'exporting the full page instead.')
    crop = FALSE
  }
  pad = rep_len(padding, 2L)  # c(vertical, horizontal)
  # When the user fixes a width (or we need to crop), measure the rendered
  # size at that width; `w`/`h` are the outer box including padding.
  if (crop || !is.null(width) || !is.null(height)) {
    d = lt_measure(html, pad, width, browser)
    w = width %||% d[1L]; h = height %||% d[2L]
    layout = crop_layout(pad, w)
  }
  if (crop && is_pdf) {
    # @page size drives the PDF page box exactly; no image post-processing.
    style = sprintf('<style>@page{size:%dpx %dpx;margin:0}%s</style>', w, h, layout)
    html = sub('</head>', paste0(style, '</head>'), html, fixed = TRUE)
    with_temp_html(html, function(f)
      xfun::browser_print(f, output, browser = browser, ...))
    return(output)
  }
  if (crop) {
    # PNG: render onto a window large enough that the table is drawn
    # unscaled at the top-left (Chromium clamps the window to a minimum size
    # and reserves some height, and scales content that overflows the
    # viewport), then crop the screenshot to the exact table box with magick.
    html = sub('</head>', paste0('<style>', layout, '</style></head>'), html, fixed = TRUE)
    png = tempfile(fileext = '.png')
    on.exit(unlink(png), add = TRUE)
    with_temp_html(html, function(f) xfun::browser_print(
      f, png, browser = browser, window_size = c(max(500L, w), h + 120L)
    ))
    img = magick::image_crop(magick::image_read(png), sprintf('%dx%d+0+0', w, h))
    magick::image_write(img, output, format = 'png')
    return(output)
  }
  # No crop: honor an explicit width/height via window_size (and body layout
  # for width), else fall back to browser_print's default full page.
  args = list(browser = browser, ...)
  if (!is.null(width) || !is.null(height)) {
    html = sub('</head>', paste0('<style>', layout, '</style></head>'), html, fixed = TRUE)
    args$window_size = c(w, h)
  }
  with_temp_html(html, function(f)
    do.call(xfun::browser_print, c(list(f, output), args)))
  output
}

has_browser = function() {
  tryCatch({xfun:::check_browser(NULL); TRUE}, error = function(e) FALSE)
}

has_node = function() nzchar(Sys.which('node'))

.onLoad = function(...) {
  register_s3(
    c('knitr', 'repr', 'repr'),
    c('knit_print', 'repr_html', 'repr_text')
  )
}
