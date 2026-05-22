# Rendering: turn an lt_tbl into HTML.
#
# Strategy: emit a `<script class="lt-spec" type="application/json">` block
# carrying the data + structural spec. The JS runtime (lt.js) auto-scans
# such blocks on DOMContentLoaded and replaces each with the rendered
# <table>. One runtime per page renders any number of tables.
# No server-rendered <table>, no element ids.

# Apply fmt_number ops to the data, returning a character data frame ready
# for emission. Number formatting happens in R so the JS layer only deals
# with structural ops.
apply_formats = function(x) {
  d = x$data
  out = d
  for (j in seq_along(out)) out[[j]] = as.character(out[[j]])
  for (op in x$ops) {
    if (op$type != 'fmt_number') next
    for (col in op$columns) {
      if (col %in% names(d) && is.numeric(d[[col]])) {
        v = formatC(d[[col]], format = 'f', digits = op$decimals, big.mark = op$big_mark)
        v[is.na(d[[col]])] = NA_character_
        out[[col]] = v
      }
    }
  }
  # Apply substitutions before blanking NAs (so we can distinguish NA from "")
  for (op in x$ops) {
    if (op$type != 'sub') next
    cols = op$columns %||% names(out)
    for (col in cols) {
      if (!col %in% names(out)) next
      v = out[[col]]
      # small threshold (compare against original numeric values)
      if (!is.null(op$small) && col %in% names(d) && is.numeric(d[[col]])) {
        i = !is.na(d[[col]]) & d[[col]] != 0 & abs(d[[col]]) < op$small
        v[i] = op$small_text %||% paste0('<', op$small)
      }
      # zero substitution (check original numeric values)
      if (!is.null(op$zero) && col %in% names(d) && is.numeric(d[[col]])) {
        v[!is.na(d[[col]]) & d[[col]] == 0] = op$zero
      }
      # missing substitution
      if (!is.null(op$missing)) {
        v[is.na(d[[col]])] = op$missing
      }
      out[[col]] = v
    }
  }
  for (j in seq_along(out)) {
    v = out[[j]]; v[is.na(v)] = ''; out[[j]] = v
  }
  # Apply merge ops: combine columns using pattern
  for (op in x$ops) {
    if (op$type != 'merge') next
    cols = op$columns
    if (!all(cols %in% names(out))) next
    target = cols[1]
    pat = op$pattern
    nr = nrow(out)
    merged = character(nr)
    for (i in seq_len(nr)) {
      vals = vapply(cols, function(c) out[[c]][i], '')
      if (is.null(pat)) {
        merged[i] = paste(vals[nzchar(vals)], collapse = ' ')
      } else {
        remaining = pat
        result = ''
        while (nzchar(remaining)) {
          m = regexpr('<<.*?>>', remaining, perl = TRUE)
          if (m < 0) {
            result = paste0(result, sub_refs(remaining, vals))
            break
          }
          if (m > 1) result = paste0(result, sub_refs(substr(remaining, 1, m - 1), vals))
          block = substr(remaining, m + 2, m + attr(m, 'match.length') - 3)
          refs = as.integer(regmatches(block, gregexpr('(?<=\\{)\\d+(?=\\})', block, perl = TRUE))[[1]])
          if (!length(refs) || !any(vals[refs] == ''))
            result = paste0(result, sub_refs(block, vals))
          remaining = substr(remaining, m + attr(m, 'match.length'), nchar(remaining))
        }
        merged[i] = result
      }
    }
    out[[target]] = merged
  }
  out
}

# Replace {1}, {2}, ... placeholders with values
sub_refs = function(s, vals) {
  for (k in seq_along(vals)) s = gsub(paste0('{', k, '}'), vals[k], s, fixed = TRUE)
  s
}

# Build the spec list serialised to JSON for the JS layer to consume. Empty
# fields are omitted so the JSON stays compact AND so the JS doesn't have to
# defend against `{}` (xfun::tojson serialises empty list() as `{}`).
build_spec = function(x) {
  d = apply_formats(x)
  skip = c(x$row_group, x$row_label)
  # Collect hidden columns (auto-hide from lt_merge)
  hidden = character()
  for (op in x$ops) {
    if (op$type == 'merge' && isTRUE(op$hide)) hidden = c(hidden, op$columns[-1])
  }
  visible = setdiff(names(d), c(skip, hidden))
  if (!length(visible)) stop('table has no visible columns')

  header = list(); spanners = list(); footnotes = list()
  notes = character(); manual_groups = list()

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
    row_group = {
      manual_groups[[length(manual_groups) + 1L]] = list(label = op$label, rows = op$rows)
    },
    fmt_number = NULL,
    align = NULL,
    cols_label = NULL,
    merge = NULL,
    sub = NULL,
    indent = NULL,
    style = NULL,
    cols_width = NULL,
    group_order = NULL,
    cols_move = NULL,
    stubhead = NULL,
    stop('unknown op type: ', op$type)
  )

  groups = list()
  if (!is.null(x$row_group)) {
    g = as.character(x$data[[x$row_group]])
    rl = rle(g)
    end = cumsum(rl$lengths)
    start = end - rl$lengths + 1L
    for (i in seq_along(rl$values)) {
      groups[[length(groups) + 1L]] = list(
        label = rl$values[i], rows = I(seq.int(start[i], end[i]))
      )
    }
  }
  if (length(manual_groups)) groups = c(groups, manual_groups)

  # Apply group ordering
  for (op in x$ops) {
    if (op$type != 'group_order' || !length(groups)) next
    labels = vapply(groups, `[[`, '', 'label')
    ordered_idx = match(op$order, labels)
    ordered_idx = ordered_idx[!is.na(ordered_idx)]
    rest = setdiff(seq_along(groups), ordered_idx)
    groups = groups[c(ordered_idx, rest)]
  }

  # Apply column reordering
  for (op in x$ops) {
    if (op$type != 'cols_move') next
    cols_to_move = intersect(op$columns, visible)
    if (!length(cols_to_move)) next
    rest = setdiff(visible, cols_to_move)
    if (is.null(op$after)) {
      visible = c(cols_to_move, rest)
    } else {
      pos = match(op$after, rest)
      if (!is.na(pos)) {
        visible = c(rest[seq_len(pos)], cols_to_move,
          if (pos < length(rest)) rest[(pos + 1L):length(rest)])
      }
    }
  }

  # Column alignment: default from data type, then apply manual overrides.
  align = ifelse(vapply(x$data[visible], is.numeric, FALSE), 'right', 'left')
  for (op in x$ops) {
    if (op$type != 'align') next
    idx = match(op$columns, visible)
    idx = idx[!is.na(idx)]
    align[idx] = op$align
  }

  # Column labels: default to column names, then apply overrides.
  col_labels = visible
  for (op in x$ops) {
    if (op$type != 'cols_label') next
    for (nm in names(op$labels)) {
      idx = match(nm, visible)
      if (!is.na(idx)) col_labels[idx] = op$labels[[nm]]
    }
  }

  # Column widths
  col_widths = NULL
  for (op in x$ops) {
    if (op$type != 'cols_width') next
    if (is.null(col_widths)) col_widths = rep('', length(visible))
    for (nm in names(op$widths)) {
      idx = match(nm, visible)
      if (!is.na(idx)) col_widths[idx] = op$widths[[nm]]
    }
  }
  if (!is.null(col_widths) && all(col_widths == '')) col_widths = NULL

  # Collect indent levels per row (only if stub exists)
  indent = NULL
  if (!is.null(x$row_label)) {
    ind = integer(nrow(d))
    for (op in x$ops) {
      if (op$type != 'indent') next
      ind[op$rows] = op$level
    }
    if (any(ind > 0L)) indent = I(ind)
  }

  # Stubhead label override
  stub_label = x$row_label
  for (op in x$ops) {
    if (op$type == 'stubhead') stub_label = op$label
  }

  # Collect cell styles as [{css, columns, rows}]
  styles = list()
  for (op in x$ops) {
    if (op$type != 'style') next
    s = list(css = op$css)
    if (!is.null(op$columns)) s$columns = I(op$columns)
    if (!is.null(op$rows))    s$rows = op$rows
    styles[[length(styles) + 1L]] = s
  }

  rows_mat = lapply(seq_len(nrow(d)), function(i) I(unname(unlist(d[i, visible]))))
  spec = list(
    columns = I(visible),
    col_labels = if (!identical(col_labels, visible)) I(col_labels),
    col_widths = if (!is.null(col_widths)) I(col_widths),
    align = I(unname(align)),
    rows = rows_mat,
    stub = if (!is.null(x$row_label)) I(as.character(d[[x$row_label]])),
    stub_label = stub_label,
    indent = indent,
    header = header,
    spanners = spanners,
    footnotes = footnotes,
    notes = as.list(notes),
    row_groups = groups,
    styles = styles
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
  # Linked (not inlined) so litedown's embed_resources() dedups them across
  # tables: identical <link href> / <script src> tags collapse to one.
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
