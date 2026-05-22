# Rendering: turn an lt_tbl into HTML.
#
# Strategy: emit a <script> block that pushes a JSON spec (raw data +
# declarative ops) onto LT.q. The JS runtime (lt.js) applies ops
# (format, sub, merge, etc.) to the raw data and renders the <table>.
# One runtime per page renders any number of tables.

# Build the spec list serialised to JSON for the JS layer to consume.
# The spec carries raw data as column arrays and declarative ops.
build_spec = function(x) {
  d = x$data

  # Collect ops to emit in spec (order matters for application)
  ops = list()
  for (op in x$ops) {
    out_op = switch(
      op$type,
      fmt_number = list(type = 'fmt_number', columns = I(op$columns),
        decimals = op$decimals, big_mark = op$big_mark),
      sub = {
        s = list(type = 'sub')
        if (!is.null(op$columns)) s$columns = I(op$columns)
        if (!is.null(op$missing)) s$missing = op$missing
        if (!is.null(op$zero))    s$zero = op$zero
        if (!is.null(op$small))   s$small = op$small
        if (!is.null(op$small_text)) s$small_text = op$small_text
        s
      },
      merge = list(type = 'merge', columns = I(op$columns),
        pattern = op$pattern, hide = op$hide),
      align = list(type = 'align', columns = I(op$columns), align = op$align),
      cols_label = list(type = 'cols_label', labels = op$labels),
      cols_width = list(type = 'cols_width', widths = op$widths),
      cols_move = list(type = 'cols_move', columns = I(op$columns),
        after = op$after),
      indent = list(type = 'indent', rows = op$rows, level = op$level),
      style = {
        s = list(type = 'style', css = op$css)
        if (!is.null(op$columns)) s$columns = I(op$columns)
        if (!is.null(op$rows))    s$rows = op$rows
        s
      },
      row_group = list(type = 'row_group', label = op$label, rows = op$rows),
      group_order = list(type = 'group_order', order = I(op$order)),
      stubhead = list(type = 'stubhead', label = op$label),
      header = NULL,
      spanner = NULL,
      footnote = NULL,
      note = NULL,
      NULL
    )
    if (!is.null(out_op)) ops[[length(ops) + 1L]] = out_op
  }

  # Structural fields (header, spanners, footnotes, notes)
  header = list()
  spanners = list()
  footnotes = list()
  notes = character()
  for (op in x$ops) switch(
    op$type,
    header = {
      if (!is.null(op$title))    header$title    = op$title
      if (!is.null(op$subtitle)) header$subtitle = op$subtitle
    },
    spanner = {
      spanners[[length(spanners) + 1L]] = list(label = op$label, columns = op$columns)
    },
    footnote = {
      footnotes[[length(footnotes) + 1L]] = list(text = op$text, location = op$location)
    },
    note = {
      notes = c(notes, op$text)
    },
    NULL
  )

  spec = list(
    data = d,
    row_group = x$row_group,
    row_label = x$row_label,
    ops = ops,
    header = header,
    spanners = spanners,
    footnotes = footnotes,
    notes = as.list(notes)
  )
  spec[lengths(spec) > 0L]
}

asset_path = function(file) {
  p = system.file('www', file, package = 'lt')
  if (!nzchar(p)) p = file.path('inst', 'www', file)
  p
}

read_asset = function(file) {
  p = asset_path(file)
  if (!file.exists(p)) stop('asset not found: ', file, ' (looked at ', p, ')')
  paste(readLines(p, warn = FALSE, encoding = 'UTF-8'), collapse = '\n')
}

asset_url = function(file) {
  url = getOption('lt.assets_url')
  if (!is.null(url)) return(paste0(url, file))
  if (isTRUE(getOption('lt.local'))) return(paste0('file://', asset_path(file)))
  sub = if (grepl('\\.js$', file)) 'js' else 'css'
  sprintf(
    'https://cdn.jsdelivr.net/npm/@xiee/utils@%s/%s/%s',
    read.dcf(system.file('DESCRIPTION', package = 'lt'))[, 'Config/lt.js'],
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
  if (inline) paste0('<style>', read_asset('lt.css'), '</style>')
  else sprintf('<link rel="stylesheet" href="%s">', asset_url('lt.css'))
}

js_block = function(inline = TRUE) {
  if (inline) paste0('<script>', inline_safe(read_asset('lt.js')), '</script>')
  else sprintf('<script src="%s" defer></script>', asset_url('lt.js'))
}

# Per-table block: queue the spec with a reference to the current script.
# The runtime drains the queue when it loads.
spec_block = function(x) paste0(
  '<script>((window.LT=window.LT||{}).q=window.LT.q||[]).push({s:document.currentScript,d:',
  inline_safe(xfun::tojson(build_spec(x))),
  '})</script>'
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
#' @param assets If `TRUE` (default), include the CSS+JS runtime. Pass
#'   `FALSE` to emit only the spec block when the runtime is already on the
#'   page.
#' @param ... Reserved for future use.
#' @return A character scalar containing HTML.
#' @export
format.lt_tbl = function(x, fragment = TRUE, inline_assets = TRUE, assets = TRUE, ...) {
  body = paste(c(
    if (assets) css_block(inline_assets),
    spec_block(x),
    if (assets) js_block(inline_assets)
  ), collapse = '')
  if (fragment) body else paste0(
    '<!DOCTYPE html><html><head><meta charset="utf-8"><title>lt</title>',
    '<style>body{font-family:system-ui,sans-serif;padding:1em}</style></head>',
    '<body>', body, '</body></html>'
  )
}

#' Print an `lt_tbl` (Opens in the Viewer or Browser)
#'
#' @param x An `lt_tbl` object.
#' @param ... Passed to [format()].
#' @return `x`, invisibly.
#' @export
print.lt_tbl = function(x, ...) {
  xfun::html_view(format(x, fragment = FALSE, ...))
  invisible(x)
}

# knit_print: dedup the CSS+JS runtime within a document via opts_knit
# (per-document, auto-resets between knits). knitr is loaded when
# knit_print fires, so this never reaches knitr:: when knitr is absent.
.knit_flag = 'lt.assets_added'

knit_print.lt_tbl = function(x, ...) {
  first = !isTRUE(knitr::opts_knit$get(.knit_flag))
  if (first) knitr::opts_knit$set(stats::setNames(list(TRUE), .knit_flag))
  structure(format(x, assets = first), class = c('knit_asis', 'html'))
}

# record_print (litedown / xfun::record): we always emit the assets block.
# knitr is not a hard dep so we don't reach into opts_knit here. The runtime
# itself self-guards (`if (root.LT) return`) against duplicate execution,
# so the cost is only the inline bytes — which we accept to avoid coupling
# to knitr. (Same trade-off gglite makes for record_print.g2.)
#
# Each element in the new_record() vector is a separate Markdown block —
# CommonMark requires blank lines between raw-HTML blocks for them to be
# recognised as raw, so we hand back css / js / spec as separate strings
# rather than a single concatenation.

#' @importFrom xfun record_print
#' @export
record_print.lt_tbl = function(x, ...) xfun::new_record(c(
  css_block(inline = FALSE), spec_block(x), js_block(inline = FALSE), ''
), 'asis')

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

.onLoad = function(...) {
  register_s3(
    c('knitr', 'repr', 'repr'),
    c('knit_print', 'repr_html', 'repr_text')
  )
}
