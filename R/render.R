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

# Op types rendered as inline graphics by the lt-plot.js module (error bars,
# and later sparklines). A table using any of them needs that module's assets
# (lt-plot.js, lt-plot.css) in addition to the core runtime.
.plot_ops = c('errorbar', 'sparkline', 'dotplot')
has_plot = function(x) any(vapply(
  x$ops, function(o) isTRUE(o$type %in% .plot_ops), logical(1)
))

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

# Inline the CSS/JS runtime assets. `files` are file names under inst/www, so
# the interactivity extension rides along for the tables that opt in. Emit once
# per page; the runtime is idempotent if included twice, but the bytes are
# wasteful — pass `inline = FALSE` for the linked form (litedown dedups
# identical <link>/<script src> tags).
css_block = function(files, inline = TRUE) {
  if (!length(files)) return()
  if (inline) c('<style>', unlist(lapply(files, read_asset)), '</style>')
  else sprintf('<link rel="stylesheet" href="%s">', vapply(files, asset_url, ''))
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

# Each asset gets its own <script>: they are separate top-level programs, and
# `defer` keeps linked ones executing in document order (core before plugins).
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
  # Drop css/rules (emitted separately as <link>/<style>, or attached via
  # lt_dependency()) and prep exactly as the render/queue paths expect. Also drop
  # any leftover crosstalk metadata: lt_interactive() moves it into the spec, so
  # a top-level copy only lingers (unused) when the table was never made
  # interactive.
  x$css = x$rules = x$crosstalk = NULL
  x = with_missing(with_col_order(x))
  x[lengths(x) > 0L]
}

# Per-table block: queue the spec with a reference to the current script.
# The runtime drains the queue when it loads.
spec_block = function(x) {
  c(
    '<script>((window.LT=window.LT||{}).q=window.LT.q||[]).push({s:document.currentScript,d:',
    inline_safe(xfun::tojson(lt_spec(x))),
    '})</script>'
  )
}

# Record the data frame's column order explicitly, but only when it is at risk.
# A JSON object reorders "array index" keys: strings that are the canonical
# form of an integer in 0 .. 2^32 - 2 are sorted ascending and moved ahead of
# all other keys (JS spec). So a column named "1" or "2" would jump to the
# front, scrambling the rendered order. Other numeric-looking names ("-1",
# "1.5", "01", "+1") are ordinary string keys and keep insertion order, so
# they need no help. When any column name is an array index, we ship the full
# order and lt.js reads `columns` in preference to Object.keys(); otherwise the
# field is omitted (it would just duplicate the data's key order).
any_array_index = function(nms) {
  any(i <- grepl('^(0|[1-9][0-9]*)$', nms)) && any(as.numeric(nms[i]) < 2^32 - 1)
}
with_col_order = function(x) {
  nms = names(x$data)
  if (length(nms) && any_array_index(nms)) x$columns = I(nms)
  x
}

# Display text for missing (NA) cells. The runtime defaults to an em dash, so
# we only ship `missing` when the `lt.missing` option is set: to a replacement
# string, or to "" to keep NAs blank (an empty string is still serialized, to
# override the runtime default). A per-column lt_sub(missing=) overrides this.
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
  # lt-plot.js must load before core (core reads LT.cells when it drains the
  # queue), so it leads the script list.
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

# knit_print: dedup the CSS+JS runtime within a document via opts_knit
# (per-document, auto-resets between knits). knitr is loaded when
# knit_print fires, so this never reaches knitr:: when knitr is absent.
.knit_flag = 'lt.assets_added'
.css_flag = 'lt.css_added'
.int_flag = 'lt.interactive_added'
.plot_flag = 'lt.plot_added'

# TRUE the first time `flag` is seen in this knit (recording it, so later calls
# return FALSE): the gate that emits each shared asset bundle once per document.
knit_once = function(flag) {
  first = !isTRUE(knitr::opts_knit$get(flag))
  if (first) knitr::opts_knit$set(stats::setNames(list(TRUE), flag))
  first
}

# Wrap rendered table HTML with extra asset tags — used to attach a late
# extension's tags around a table whose format() emitted no core assets.
wrap_assets = function(html, before = NULL, after = NULL)
  paste(c(before, html, after), collapse = '\n')

knit_print.lt_tbl = function(x, ...) {
  if (is.list(opts <- getOption('lt.lt_static'))) return(structure(
    do.call(lt_static, c(list(x), opts)), class = 'knit_asis'
  ))
  first = knit_once(.knit_flag)
  # Each extension is gated on its own flag: the first table that uses it need
  # not be the first table overall, so when it isn't, format() has no core
  # assets to carry it and we wrap its tags around the table below.
  int_first  = !is.null(x$interactive) && knit_once(.int_flag)
  plot_first = has_plot(x) && knit_once(.plot_flag)
  # Dedup user CSS (from lt_css()) across the document: a stylesheet shared
  # by many tables (e.g. a package theme) should be emitted once. Identical
  # <link> hrefs would dedup in the browser, but inlined <style> blocks
  # (absolute paths) would not — so filter against what's already emitted.
  seen = knitr::opts_knit$get(.css_flag)
  x$css = setdiff(x$css, seen)
  if (length(x$css))
    knitr::opts_knit$set(stats::setNames(list(c(seen, x$css)), .css_flag))
  html = format(x, assets = first)
  # A late extension goes where format() would: the interactivity script after
  # the core runtime; the graphics module (whose renderer must exist before
  # core builds) entirely before the table.
  if (int_first && !first)
    html = wrap_assets(html, css_block('lt-interactive.css'), js_block('lt-interactive.js'))
  if (plot_first && !first)
    html = wrap_assets(html, c(css_block('lt-plot.css'), js_block('lt-plot.js')))
  structure(xfun::raw_string(html), class = c('knit_asis', 'html'))
}

# record_print (litedown / xfun::record): for HTML output emit assets + spec;
# for non-HTML output (markdown), render to static HTML via lt_static().

#' @importFrom xfun record_print
#' @export
record_print.lt_tbl = function(x, ...) {
  if (is.list(opts <- getOption('lt.lt_static')))
    return(xfun::new_record(c(do.call(lt_static, c(list(x), opts)), ''), 'asis'))
  # litedown dedups identical linked tags across the document, so the
  # extension's <link>/<script src> can be emitted for every interactive table.
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


# Build the HTML for lt_export()'s .html output. `method`:
#   "raw"     -> the JavaScript-spec HTML (the table is built client-side by
#                lt.js at view time); no external tool runs.
#   "node"    -> run lt.js in Node.js to bake a static <table>.
#   "browser" -> run lt.js in a headless Chromium browser (via browser_dom).
#   "auto"    -> node if available, else browser.
# `css` includes the lt.css runtime stylesheet (user CSS from lt_css() always
# is); `fragment = FALSE` wraps the result in a full HTML document. `tidy`
# pretty-prints the baked <table> with line breaks and indentation (ignored
# for method = "raw", which is a JS spec, not a static table).
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
# indent by nesting depth. lt controls the exact markup (a fixed set of `lt-*`
# tags, no arbitrary user HTML), so a targeted tag-based indenter is enough;
# this is not a general HTML tidier.
tidy_html = function(html) {
  # Containers get their own line for both open and close tags; cells (th/td)
  # break before the opening tag only, so a leaf like <td>1</td> stays on one
  # line with its content inline.
  box = 'div|table|thead|tbody|tfoot|caption|colgroup|tr'
  html = gsub(sprintf('(</?(?:%s)\\b|<t[hd]\\b)', box), '\n\\1', html, perl = TRUE)
  lines = unlist(strsplit(html, '\n'))
  lines = lines[nzchar(lines)]
  depth = 0L; out = character(length(lines))
  for (i in seq_along(lines)) {
    ln = lines[i]
    if (grepl('^</', ln)) depth = max(0L, depth - 1L)
    out[i] = paste0(strrep('  ', depth), ln)
    # An opening tag whose matching close isn't on the same line opens a deeper
    # level for the following lines; a leaf tag (e.g. <td>1</td>) does not.
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
  # lt-plot.js before lt.js so its renderer is registered when core builds.
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
  d = as.integer(m[-1L])
  # scrollWidth is the floor of the table's fractional natural width. Pinning
  # the body to that floored width leaves it a sub-pixel too narrow, so a cell
  # wraps and the table grows taller than the measured height, spilling the
  # PDF onto a second page (platform-dependent: seen on macOS, not Linux). Add
  # 1px so the body is never narrower than the content and never re-wraps.
  d[1L] = d[1L] + 1L
  # scrollHeight is rounded to an integer, and the 0.85em footer text gives the
  # body a fractional height (e.g., 316.39px with two footnote rows, rounded
  # down to 316). A page box of exactly scrollHeight px then overflows by a
  # sub-pixel, and Chromium starts a second page holding the repeated <thead>
  # and the <tfoot> (also seen on macOS). Add 1px so the page is never
  # shorter than the content.
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
#' if (lt:::has_browser()) {
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
  # HTML output (also the target when `output` is NA, since there's no
  # extension to infer a format from): no browser needed at view time.
  if (is.na(output) || tolower(xfun::file_ext(output)) == 'html') {
    html = lt_static(x, method, css, fragment, tidy)
    if (is.na(output)) return(html)
    xfun::write_utf8(html, output)
    return(output)
  }
  # PDF/PNG are rendered from a temporary directory (with_temp_html), so a
  # relative user-CSS href would not resolve there. Absolutize existing local
  # files for this render only; x$css itself stays as the user gave it, keeping
  # HTML output portable.
  if (length(p <- x$css) && any(i <- file.exists(p)))
    x$css[i] = xfun::normalize_path(p[i])

  html = format(x, fragment = FALSE)
  is_pdf = tolower(xfun::file_ext(output)) == 'pdf'
  # PNG cropping needs magick to trim Chromium's screenshot (its --screenshot
  # size is the window size, which we can't shrink below Chromium's minimums).
  # PDF cropping needs no extra package: an @page rule sets the page box.
  if (crop && !is_pdf && !xfun::loadable('magick')) {
    warning('Cropping PNG output requires the magick package; ',
            'exporting the full page instead.')
    crop = FALSE
  }
  pad = rep_len(padding, 2L)  # c(vertical, horizontal)
  # When cropping or when the user fixes a width, measure the rendered size
  # (at that width); `w`/`h` are the outer box including padding.
  if (crop || !is.null(width)) {
    d = lt_measure(html, pad, width, browser)
    w = width %||% d[1L]; h = d[2L]
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
  # No crop: honor an explicit width via body layout + window_size, else fall
  # back to browser_print's default full page.
  args = list(browser = browser, ...)
  if (!is.null(width)) {
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

# Whether a static <table> can be baked (method = 'node'/'browser'), i.e. an
# external renderer is available. FALSE in environments without one, e.g. webR
# (which has neither Node.js nor a launchable headless browser), where
# lt_export()'s baking/PDF/PNG paths would error.
can_bake = function() has_node() || has_browser()

.onLoad = function(...) {
  register_s3(
    c('knitr', 'repr', 'repr'),
    c('knit_print', 'repr_html', 'repr_text')
  )
}
