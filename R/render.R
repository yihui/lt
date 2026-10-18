# Rendering: turn an lt_tbl into HTML.
#
# Strategy: emit a <script> that pushes a JSON spec (raw data + declarative
# ops) onto LT.q. The JS runtime (lt.js) applies ops (format, sub, merge, etc.)
# and renders the <table>. One runtime per page renders any number of tables.

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

# Op types rendered as inline graphics by lt-plot.js (error bars, later
# sparklines). Tables using any need that module's assets (lt-plot.js,
# lt-plot.css) besides the core runtime.
.plot_ops = c('errorbar', 'sparkline', 'dotplot')
has_plot = function(x) any(vapply(
  x$ops, function(o) isTRUE(o$type %in% .plot_ops), logical(1)
))

# Inlined <script> content must not contain `</script` (case-insensitive); the
# HTML parser would end the script there. `<\/script` is harmless in JS strings,
# JSON, and comments. Other `</tag>` sequences stay untouched: rewriting them
# inside a JS regex literal (e.g. `/</g`) would break it. lt.js uses `[<]` in
# its only HTML-escape regex so this minimal escape suffices.
inline_safe = function(s) gsub(
  '</(script)', '<\\\\/\\1', s, perl = TRUE, ignore.case = TRUE
)

# Inline CSS/JS runtime assets. `files` are names under inst/www, so the
# interactivity extension rides along for opt-in tables. Emit once per page;
# runtime is idempotent but repeats waste bytes. `inline = FALSE` gives linked
# form (litedown dedups identical <link>/<script src> tags).
css_block = function(files, inline = TRUE) {
  if (!length(files)) return()
  if (inline) c('<style>', unlist(lapply(files, read_asset)), '</style>')
  else sprintf('<link rel="stylesheet" href="%s">', vapply(files, asset_url, ''))
}

# User CSS path -> tag. URLs and relative paths become <link> (browser dedups
# identical hrefs). Absolute paths are inlined as <style> by default: file://
# only resolves on the client's filesystem, breaking RStudio Server, Shiny
# Server, and remote renders. `local` opts into file:// for record_print, where
# litedown inlines such files at assembly time.
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

# One <script> per asset: separate top-level programs. `defer` keeps linked
# ones in document order (core before plugins).
js_block = function(files, inline = TRUE) {
  unlist(lapply(files, function(f) if (inline)
    c('<script>', inline_safe(read_asset(f)), '</script>')
    else sprintf('<script src="%s" defer></script>', asset_url(f))
  ))
}

#' Extract a table's render-ready spec
#'
#' Return the JSON-ready spec for an [lt()] table: the raw data plus the
#' declarative ops (and any [lt_interactive()] options), prepared exactly as the
#' JavaScript runtime expects. This is the payload the runtime consumes, so
#' another widget can embed an lt table by shipping this spec (e.g.
#' `xfun::tojson(lt_spec(x))`) and rendering it client-side on demand with
#' `LT.render(container, spec)` (or `LT.buildHtml(spec)`). Styling from
#' [lt_css()] and CSS rules is dropped; attach the runtime assets separately
#' (see [lt_dependency()]).
#'
#' @param x An `lt_tbl` object.
#' @return A named list of spec fields (`data`, `ops`, and any others set on the
#'   table), ready to serialize to JSON.
#' @export
#' @examples
#' spec = lt_spec(lt(head(mtcars)) |> lt_interactive())
#' str(spec, max.level = 1)
#' xfun::tojson(spec)  # ship this, then LT.render(container, spec) in the browser
lt_spec = function(x) {
  # Drop css/rules (emitted separately as <link>/<style> or via
  # lt_dependency()); prep as the render/queue paths expect.
  x$css = x$rules = NULL
  x = with_missing(with_col_order(x))
  x[lengths(x) > 0L]
}

# Per-table block: queue the spec with a reference to the current script;
# runtime drains the queue on load.
spec_block = function(x) {
  c(
    '<script>((window.LT=window.LT||{}).q=window.LT.q||[]).push({s:document.currentScript,d:',
    inline_safe(xfun::tojson(lt_spec(x))),
    '})</script>'
  )
}

# Record column order explicitly, only when at risk. A JSON object moves
# "array index" keys (canonical integers in 0 .. 2^32 - 2) ahead of all other
# keys (JS spec), so a column named "1" would jump to the front. Other
# numeric-looking names ("-1", "1.5", "01", "+1") keep insertion order. When
# any name is an array index, ship the full order (lt.js prefers `columns` to
# Object.keys()); else omit it as redundant.
any_array_index = function(nms) {
  any(i <- grepl('^(0|[1-9][0-9]*)$', nms)) && any(as.numeric(nms[i]) < 2^32 - 1)
}
with_col_order = function(x) {
  nms = names(x$data)
  if (length(nms) && any_array_index(nms)) x$columns = I(nms)
  x
}

# Display text for NA cells. Runtime default is an em dash, so ship `missing`
# only when the `lt.missing` option is set: a replacement string, or "" to
# keep NAs blank (still serialized, to override the default). Per-column
# lt_sub(missing=) overrides.
with_missing = function(x) {
  if (is.null(x$missing) && !is.null(m <- getOption('lt.missing'))) x$missing = m
  x
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
#'   `c("css", "js")` for selective inclusion. A table with [lt_interactive()]
#'   enabled also gets the interactivity extension: its stylesheet with
#'   `"css"`, its script with `"js"`.
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
  int = !is.null(x$interactive)
  plot = has_plot(x)
  # lt-plot.js leads: core reads LT.cells when draining the queue.
  body = c(
    css_block(if ('css' %in% assets)
      c('lt.css', if (plot) 'lt-plot.css', if (int) 'lt-interactive.css'),
      inline_assets),
    user_css_block(x$css),
    rules_block(x$rules),
    spec_block(x),
    js_block(if ('js' %in% assets)
      c(if (plot) 'lt-plot.js', 'lt.js', if (int) 'lt-interactive.js'),
      inline_assets)
  )
  if (!fragment) body = html_doc(body)
  xfun::raw_string(paste(body, collapse = '\n'))
}

#' Print an `lt_tbl` (opens in the viewer or browser)
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

# knit_print: dedup CSS+JS runtime per document via opts_knit (auto-resets
# between knits). knitr is already loaded when this fires.
.knit_flag = 'lt.assets_added'
.css_flag = 'lt.css_added'
.int_flag = 'lt.interactive_added'
.plot_flag = 'lt.plot_added'

# TRUE the first time `flag` is seen in this knit (recorded, so later calls
# return FALSE): emits each shared asset bundle once per document.
knit_once = function(flag) {
  first = !isTRUE(knitr::opts_knit$get(flag))
  if (first) knitr::opts_knit$set(set_names(list(TRUE), flag))
  first
}

# Wrap table HTML with extra asset tags, to attach a late extension's tags
# when format() emitted no core assets.
wrap_assets = function(html, before = NULL, after = NULL)
  paste(c(before, html, after), collapse = '\n')

knit_print.lt_tbl = function(x, ...) {
  if (is.list(opts <- getOption('lt.lt_static'))) return(structure(
    do.call(lt_static, c(list(x), opts)), class = 'knit_asis'
  ))
  first = knit_once(.knit_flag)
  # Each extension has its own flag: the first table using it may not be the
  # first overall, so format() has no core assets to carry it; wrap its tags
  # around the table below.
  int_first  = !is.null(x$interactive) && knit_once(.int_flag)
  plot_first = has_plot(x) && knit_once(.plot_flag)
  # Dedup user CSS (lt_css()) across the document: a stylesheet shared by many
  # tables should be emitted once. Identical <link> hrefs dedup in the
  # browser, inlined <style> blocks (absolute paths) don't, so filter here.
  seen = knitr::opts_knit$get(.css_flag)
  x$css = setdiff(x$css, seen)
  if (length(x$css))
    knitr::opts_knit$set(set_names(list(c(seen, x$css)), .css_flag))
  html = format(x, assets = first)
  # Late extension goes where format() would put it: interactivity script
  # after core; graphics module (renderer must exist before core builds)
  # entirely before the table.
  if (int_first && !first)
    html = wrap_assets(html, css_block('lt-interactive.css'), js_block('lt-interactive.js'))
  if (plot_first && !first)
    html = wrap_assets(html, c(css_block('lt-plot.css'), js_block('lt-plot.js')))
  structure(xfun::raw_string(html), class = c('knit_asis', 'html'))
}

# record_print (litedown / xfun::record): HTML output emits assets + spec;
# non-HTML (markdown) renders static HTML via lt_static().

#' @importFrom xfun record_print
#' @export
record_print.lt_tbl = function(x, ...) {
  if (is.list(opts <- getOption('lt.lt_static')))
    return(xfun::new_record(c(do.call(lt_static, c(list(x), opts)), ''), 'asis'))
  # litedown dedups identical linked tags across the document, so the
  # extension's tags can be emitted for every interactive table.
  int = !is.null(x$interactive)
  plot = has_plot(x)
  xfun::new_record(c(
    css_block(c('lt.css', if (plot) 'lt-plot.css', if (int) 'lt-interactive.css'),
      inline = FALSE),
    user_css_block(x$css, local = TRUE),
    rules_block(x$rules), spec_block(x),
    js_block(c(if (plot) 'lt-plot.js', 'lt.js', if (int) 'lt-interactive.js'),
      inline = FALSE), ''
  ), 'asis')
}

# Each Jupyter cell is a sandboxed document: always emit a full page with
# assets; no cross-cell dedup.
repr_html.lt_tbl = function(obj, ...) format(obj, fragment = FALSE)

repr_text.lt_tbl = function(obj, ...) {
  sprintf('lt_tbl (%d rows x %d cols)', nrow(obj$data), ncol(obj$data))
}

# Register S3 methods for knitr / repr (Jupyter) at .onLoad, no hard deps.
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


# Build HTML for lt_export()'s .html output. `method`:
#   "raw"     -> JavaScript-spec HTML (lt.js builds the table at view time);
#                no external tool.
#   "node"    -> run lt.js in Node.js to bake a static <table>.
#   "browser" -> run lt.js in headless Chromium (via browser_dom).
#   "auto"    -> node if available, else browser.
# `css` includes the lt.css runtime stylesheet (lt_css() CSS is always
# included); `fragment = FALSE` wraps in a full HTML document. `tidy`
# pretty-prints the baked <table> (ignored for "raw", a JS spec).
lt_static = function(
  x, method = c('auto', 'node', 'browser', 'raw'), css = TRUE, fragment = FALSE,
  tidy = FALSE
) {
  method = match.arg(method)
  if (method == 'raw') return(format(
    x, fragment = fragment, assets = c(if (css) 'css', 'js')
  ))
  if (method == 'auto') method = if (has_node()) 'node' else if (has_browser()) 'browser'
  if (is.null(method)) stop(
    'No rendering method available. Install a Chromium-based browser or Node.js.'
  )
  html = switch(method, browser = lt_static_browser(x, css), node = lt_static_node(x, css))
  if (tidy) html = tidy_html(html)
  if (!fragment) html = html_doc(html)
  xfun::raw_string(html)
}

# Pretty-print lt's baked <table> HTML: break before each structural tag and
# indent by depth. lt controls the markup (fixed `lt-*` tags, no arbitrary user
# HTML), so a targeted indenter suffices; not a general tidier.
tidy_html = function(html) {
  # Containers break on open and close tags; cells (th/td) break before the
  # opening tag only, keeping a leaf like <td>1</td> on one line.
  box = 'div|table|thead|tbody|tfoot|caption|colgroup|tr'
  html = gsub(sprintf('(</?(?:%s)\\b|<t[hd]\\b)', box), '\n\\1', html, perl = TRUE)
  lines = unlist(strsplit(html, '\n'))
  lines = lines[nzchar(lines)]
  depth = 0L; out = character(length(lines))
  for (i in seq_along(lines)) {
    ln = lines[i]
    if (grepl('^</', ln)) depth = max(0L, depth - 1L)
    out[i] = paste0(strrep('  ', depth), ln)
    # An opening tag whose close isn't on the same line deepens the following
    # lines; a leaf (e.g. <td>1</td>) doesn't.
    if (grepl('^<[^/]', ln) && !grepl('^<(\\w+)\\b[^>]*>.*</\\1>\\s*$', ln, perl = TRUE))
      depth = depth + 1L
  }
  out
}

lt_static_browser = function(x, css = TRUE) {
  f = tempfile(fileext = '.html')
  on.exit(unlink(f), add = TRUE)
  xfun::write_utf8(format(x, fragment = FALSE, assets = c(if (css) 'css', 'js')), f)
  xfun::browser_dom(f, fragment = TRUE)
}

lt_static_node = function(x, css = TRUE) {
  runner = pkg_file('js', 'run-lt.js')
  plot = has_plot(x)
  # lt-plot.js before lt.js: its renderer must be registered when core builds.
  js = pkg_file('www', c(if (plot) 'lt-plot.js', 'lt.js'))
  spec = x; spec$css = spec$rules = NULL
  if (!length(spec$ops)) spec$ops = NULL
  spec = with_missing(with_col_order(spec))
  json = xfun::tojson(spec)
  out = system2('node', shQuote(c(runner, js)), input = json, stdout = TRUE)
  if (!is.null(attr(out, 'status'))) stop('Node.js failed to render the lt table.')
  Encoding(out) = 'UTF-8'
  c(
    css_block(c(if (css) 'lt.css', if (css && plot) 'lt-plot.css')),
    user_css_block(x$css), rules_block(x$rules), out
  )
}

# Write `html` to a temp file, run it through headless Chromium via `fun`,
# clean up. Shared by the measure (browser_dom) and render (browser_print)
# passes.
with_temp_html = function(html, fun) {
  f = tempfile(fileext = '.html')
  on.exit(unlink(f), add = TRUE)
  xfun::write_utf8(html, f)
  fun(f)
}

# Layout CSS shared by measure and render passes: zero page margins so the
# table sits flush top-left, add crop padding, set body width. Both passes MUST
# use identical layout so pass-1 size matches pass 2. `pad` is c(vertical,
# horizontal) in CSS px; `width` is outer body width in px (NULL = shrink to
# table's natural width). box-sizing keeps `padding` inside `width`.
crop_layout = function(pad, width = NULL) sprintf(paste0(
  'html,body{margin:0!important}',
  'body{box-sizing:border-box;padding:%dpx %dpx!important;width:%s}'
), pad[1L], pad[2L], if (is.null(width)) 'max-content' else paste0(width, 'px'))

# Measure the rendered table's full pixel size (including crop padding).
# Chromium runs lt.js, so the box is known only after JS builds the table:
# inject a load handler that stamps body.scrollWidth/scrollHeight onto <body>
# as data attributes, dump the DOM, parse them back. Body scroll size, not the
# table's bounding box, because parts of the table (caption border, footer
# spacing) extend past its border-box; the table box alone undercounts height
# and spills the PDF onto a second page. Returns integer c(width, height).
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
  d = as.integer(m[-1L])
  # scrollWidth floors the table's fractional natural width. Pinning the body
  # to that leaves it a sub-pixel too narrow, so a cell wraps and the table
  # grows taller than measured, spilling the PDF onto a second page
  # (platform-dependent: macOS, not Linux). Add 1px so the body never re-wraps.
  d[1L] = d[1L] + 1L
  # scrollHeight is rounded to an integer, and the 0.85em footer text gives the
  # body a fractional height (e.g., 316.39px rounded down to 316). A page box
  # of exactly scrollHeight px then overflows by a sub-pixel, and Chromium
  # starts a second page with the repeated <thead> and <tfoot> (also macOS).
  # Add 1px so the page is never shorter than the content.
  d[2L] = d[2L] + 1L
  d
}

#' Export an lt table to a file
#'
#' Save a table to disk. The output format is chosen from the file extension
#' of `output`: `.html` writes an HTML table, `.pdf` writes a vector PDF, and
#' any other extension writes a PNG. PDF and PNG are produced by rendering the
#' table in a headless Chromium browser (via [xfun::browser_print()]).
#'
#' For `.html` output, `method` controls how the `<table>` is produced:
#' `"raw"` writes the JavaScript-spec HTML, so the table is built in the
#' browser by the lt.js runtime when the file is viewed; the other methods
#' bake a static `<table>` up front by running lt.js once (via `"node"` in
#' Node.js or `"browser"` in a headless Chromium browser; `"auto"` picks Node
#' if available, else the browser), so the saved file needs no JavaScript to
#' view. `method`, `css`, `fragment`, and `tidy` apply only to `.html` output.
#'
#' @param x An `lt_tbl` object.
#' @param output Output file path. Its extension selects the format: `.html`,
#'   `.pdf`, or (otherwise) PNG. If `NA`, the HTML is returned as a string
#'   instead of being written to a file.
#' @param method How to produce the HTML `<table>`: `"auto"`, `"node"`,
#'   `"browser"`, or `"raw"` (see Details). Applies only to `.html` output.
#' @param css Whether to include the lt.css runtime stylesheet in the HTML
#'   output. User CSS from [lt_css()] is always included. Applies only to
#'   `.html` output.
#' @param fragment If `FALSE` (default), wrap the HTML in a full HTML document;
#'   if `TRUE`, return only the table fragment. Applies only to `.html`
#'   output.
#' @param tidy Whether to pretty-print the baked `<table>` with line breaks and
#'   indentation. Applies only to `.html` output baked by `"node"` or
#'   `"browser"` (ignored for `method = "raw"`, which is a JavaScript spec).
#' @param crop Whether to crop the PDF/PNG tightly to the table, removing the
#'   surrounding page whitespace. This adds a preliminary browser pass to
#'   measure the rendered table. Set to `FALSE` for the default full page.
#'   Cropping PNG output requires the \pkg{magick} package; without it, PNG
#'   falls back to the full page (with a warning).
#' @param width The width of the table in CSS pixels. By default (`NULL`) it
#'   shrinks to the table's natural width. A smaller `width` wraps cell
#'   content; a larger one pads the table.
#' @param padding Padding in CSS pixels to keep around the table when
#'   cropping. A single value (all sides) or a length-two vector
#'   `c(vertical, horizontal)`.
#' @param browser Path to the Chromium-based browser; passed to
#'   [xfun::browser_print()]. `NULL` (default) auto-detects.
#' @param ... Passed to [xfun::browser_print()] for PDF/PNG output. To add
#'   extra Chromium flags via its `args`, keep `"default"` in the vector (e.g.
#'   `args = c("default", "--force-device-scale-factor=2")`); `"default"` is
#'   what makes `browser_print()` add the headless and print flags, so dropping
#'   it opens the file in a desktop browser and writes nothing.
#' @return The `output` path, or (when `output` is `NA`) the HTML as a string.
#' @section Global option:
#' When the option `lt.lt_static` is set to a list of arguments (e.g.,
#' `options(lt.lt_static = list(css = FALSE))`), the
#' [knit_print][knitr::knit_print] and [record_print][xfun::record_print]
#' methods emit the same static HTML table as `lt_export(x, "*.html")` (using
#' those arguments as `method`/`css`/`fragment`) instead of the default
#' JavaScript-based spec. This is useful for output formats that support raw
#' HTML but cannot run JavaScript (e.g., GitHub Flavored Markdown).
#' @export
#' @examples
#' tbl = lt(head(mtcars))
#'
#' # HTML with the JavaScript spec (table built by lt.js when viewed)
#' f1 = tempfile(fileext = '.html')
#' lt_export(tbl, f1, method = 'raw')  # file output
#'
#' # Bake a static <table> (needs Node.js or a headless browser).
#' if (lt:::can_bake())
#'   lt_export(tbl, NA, method = 'auto', fragment = TRUE, css = FALSE, tidy = TRUE)
#'
#' # PDF / PNG are rendered in a headless browser and cropped to the table.
#' f2 = tempfile(fileext = '.pdf')
#' f3 = tempfile(fileext = '.png')
#' if (lt:::has_browser(pdf = TRUE)) {
#'   lt_export(tbl, f2)
#'   lt_export(tbl, f3, width = 400)
#' }
#'
#' unlink(c(f1, f2, f3))
lt_export = function(
  x, output = 'lt.html', method = c('auto', 'node', 'browser', 'raw'),
  css = TRUE, fragment = FALSE, tidy = FALSE, crop = TRUE, width = NULL,
  padding = 8, browser = NULL, ...
) {
  # HTML output (also when `output` is NA: no extension to infer a format
  # from): no browser needed at view time.
  if (is.na(output) || tolower(xfun::file_ext(output)) == 'html') {
    html = lt_static(x, method, css, fragment, tidy)
    if (is.na(output)) return(html)
    xfun::write_utf8(html, output)
    return(output)
  }
  # PDF/PNG render from a temp directory (with_temp_html), where a relative
  # user-CSS href wouldn't resolve. Absolutize existing local files for this
  # render only; x$css stays as given, keeping HTML output portable.
  if (length(p <- x$css) && any(i <- file.exists(p)))
    x$css[i] = xfun::normalize_path(p[i])

  html = format(x, fragment = FALSE)
  is_pdf = tolower(xfun::file_ext(output)) == 'pdf'
  # PNG cropping needs magick to trim Chromium's screenshot (its size is the
  # window size, which can't shrink below Chromium's minimums). PDF cropping
  # needs no extra package: an @page rule sets the page box.
  if (crop && !is_pdf && !xfun::loadable('magick')) {
    warning('Cropping PNG output requires the magick package; ',
            'exporting the full page instead.')
    crop = FALSE
  }
  pad = rep_len(padding, 2L)  # c(vertical, horizontal)
  # When cropping or width is fixed, measure the rendered size (at that
  # width); `w`/`h` are the outer box including padding.
  if (crop || !is.null(width)) {
    d = lt_measure(html, pad, width, browser)
    w = width %||% d[1L]; h = d[2L]
    layout = crop_layout(pad, w)
  }
  if (crop && is_pdf) {
    # @page size sets the PDF page box exactly; no image post-processing.
    style = sprintf('<style>@page{size:%dpx %dpx;margin:0}%s</style>', w, h, layout)
    html = sub('</head>', paste0(style, '</head>'), html, fixed = TRUE)
    with_temp_html(html, function(f)
      xfun::browser_print(f, output, browser = browser, ...))
    return(output)
  }
  if (crop) {
    # PNG: render in a window large enough to draw the table unscaled at
    # top-left (Chromium clamps the window to a minimum, reserves some height,
    # and scales overflowing content), then crop to the table box with magick.
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
  # No crop: honor an explicit width via body layout + window_size, else use
  # browser_print's default full page.
  args = list(browser = browser, ...)
  if (!is.null(width)) {
    html = sub('</head>', paste0('<style>', layout, '</style></head>'), html, fixed = TRUE)
    args$window_size = c(w, h)
  }
  with_temp_html(html, function(f)
    do.call(xfun::browser_print, c(list(f, output), args)))
  output
}

# With `pdf = TRUE`, also check that the browser can print a PDF (it may be
# found but fail, e.g., when sandboxed). The probe takes seconds, so cache it.
has_browser = local({
  pdf_ok = NULL
  function(pdf = FALSE) {
    ok = tryCatch({xfun:::check_browser(NULL); TRUE}, error = function(e) FALSE)
    if (!ok || !pdf) return(ok)
    pdf_ok %||% (pdf_ok <<- {
      out = tempfile(fileext = '.pdf'); on.exit(unlink(out))
      tryCatch({
        with_temp_html('<title>lt</title>', function(f) xfun::browser_print(f, out))
        file.exists(out)
      }, error = function(e) FALSE)
    })
  }
})

has_node = function() nzchar(Sys.which('node'))

# Whether a static <table> can be baked (method = 'node'/'browser'), i.e. an
# external renderer exists. FALSE where none does, e.g. webR (no Node.js or
# launchable headless browser), where lt_export()'s baking/PDF/PNG would error.
can_bake = function() has_node() || has_browser()

.onLoad = function(...) {
  register_s3(
    c('knitr', 'repr', 'repr'),
    c('knit_print', 'repr_html', 'repr_text')
  )
}
