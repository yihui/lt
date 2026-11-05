# Server mode for lt_interactive(): rows stay in R, and the browser fetches each
# view (filters, search, sort, page) from a local app built on xfun::new_app().
# The client half is lt-server.js; the query protocol is described there.

# Page sizes for server mode: finite and positive (a page of every row defeats it)
server_sizes = function(pager) {
  s = setdiff(as.integer(pager), 0L)
  if (length(s)) s else c(10L, 25L, 50L, 100L)
}

# Text form of a column, as filters and sort see it (matches the browser's):
# dates and date-times as sortable text, factors as labels
txt_col = function(x) {
  if (inherits(x, 'POSIXt')) format(x, '%Y-%m-%d %H:%M:%S')
  else if (inherits(x, 'Date') || is.factor(x)) as.character(x)
  else x
}

# JS filter expressions (`x > 5`, `x == null`, `["a","b"].includes(x)`) as R
# calls on the column `x`. Only a whitelist of functions may run, since the
# expression comes from the browser. NULL if it isn't such an expression.
js_expr = function(term) {
  term = trimws(term)
  if (grepl('^\\[.*\\]\\.includes\\(\\s*x\\s*(\\?\\?\\s*null\\s*)?\\)$', term)) {
    inner = sub('^\\[(.*)\\]\\.includes.*$', '\\1', term)
    tok = regmatches(inner, gregexpr('"(?:[^"\\\\]|\\\\.)*"|null', inner, perl = TRUE))[[1]]
    vals = lapply(tok, function(t) if (t == 'null') NA_character_ else
      tryCatch(eval(parse(text = t)), error = function(e) t))
    return(call('%in%', quote(as.character(x)), unlist(vals)))
  }
  term = gsub('!==', '!=', gsub('===', '==', term, fixed = TRUE), fixed = TRUE)
  term = gsub('(!?)=\\s*null\\b', '\\1= NA_integer_', term)  # x == null
  e = tryCatch(parse(text = term, keep.source = FALSE), error = function(e) NULL)
  if (length(e) != 1L) return()
  e = e[[1]]
  ok = c(
    '(', '!', '==', '!=', '<', '>', '<=', '>=', '&', '|', '&&', '||', '+', '-',
    '*', '/', '%in%', 'c', 'is.na', 'nchar', 'tolower', 'toupper', 'x',
    'NA', 'NA_integer_', 'TRUE', 'FALSE'
  )
  if (!all(all.names(e) %in% ok)) return()
  vec = function(e) {  # scalar && and || don't vectorize
    if (!is.call(e)) return(e)
    e[] = lapply(as.list(e), vec)
    if (identical(e[[1]], quote(`&&`))) e[[1]] = quote(`&`)
    if (identical(e[[1]], quote(`||`))) e[[1]] = quote(`|`)
    e
  }
  e = vec(e)
  # `x == NA_integer_` means a missing value
  na = function(e) {
    if (!is.call(e)) return(e)
    if (is.symbol(e[[1]]) && as.character(e[[1]]) %in% c('==', '!=') &&
        identical(e[[3]], quote(NA_integer_))) {
      neg = as.character(e[[1]]) == '!='
      e = call('is.na', e[[2]])
      if (neg) e = call('!', e)
    }
    e[] = lapply(as.list(e), na)
    e
  }
  e = na(e)
  e
}

# Rows kept by a filter or search term against columns `xs` (a list of
# text-form columns), as the browser's `matcher()` decides: a term using `x` is
# an expression on the values (a leading `!` or `!=` negates: every column must
# pass, else any), anything else a case-insensitive substring of the text.
term_keep = function(term, xs) {
  term = trimws(term)
  n = length(xs[[1]])
  if (term == '') return(rep(TRUE, n))
  if (grepl('(^|[^\\w$])x([^\\w$]|$)', term, perl = TRUE) && !is.null(e <- js_expr(term))) {
    neg = grepl('^\\s*!|!=', term)
    env = new.env(parent = baseenv())
    # JS compares text to a number numerically, so only a string literal keeps
    # text as is
    numify = !grepl('"', term, fixed = TRUE) && !'is.na' %in% all.names(e)
    res = lapply(xs, function(x) {
      env$x = if (numify && !is.numeric(x)) suppressWarnings(as.numeric(as.character(x))) else x
      r = tryCatch(eval(e, env), error = function(e) rep(FALSE, n))
      r = rep_len(as.logical(r), n)
      r[is.na(r)] = neg  # a missing value passes only a negated term
      r
    })
    return(Reduce(if (neg) `&` else `|`, res))
  }
  neg = startsWith(term, '!')
  needle = tolower(trimws(if (neg) substring(term, 2) else term))
  if (needle == '') return(rep(TRUE, n))
  hit = Reduce(`|`, lapply(xs, function(x)
    !is.na(x) & grepl(needle, tolower(as.character(x)), fixed = TRUE)))
  neg != hit
}

# Row order for sort keys `s` ("a:col" / "d:col"), nulls last
server_order = function(idx, tx, s) {
  if (!length(s)) return(idx)
  dir = substr(s, 1, 1) == 'd'
  keys = lapply(sub('^.:', '', s), function(c) {
    k = tx[[c]][idx]
    if (is.logical(k)) as.integer(k) else k
  })
  idx[do.call(order, c(unname(keys), list(
    decreasing = dir, na.last = TRUE, method = 'radix'
  )))]
}

# A column's sketch for the browser (profiles and filter widgets) and the bar of
# each row in its profile: a histogram of up to 10 bins for numbers and dates,
# one bar per category (most frequent first) for text, none for text that is
# mostly distinct. Mirrors `summary()` in lt-interactive.js.
col_sketch = function(x, tx) {
  v = tx[!is.na(tx)]
  kind = if (inherits(x, c('Date', 'POSIXt'))) 'date' else if (is.numeric(x)) 'num' else
    if (is.character(x) || is.factor(x)) 'str' else 'mix'
  num = if (kind == 'date') as.numeric(x) else if (kind == 'num') as.numeric(x)
  nv = num[!is.na(num) & is.finite(num)]
  u = unique(v)
  s = list(
    len = length(x), na = sum(is.na(x)), some = any(v != ''), kind = kind,
    m = length(u)
  )
  if (length(nv)) {
    s$int = all(nv == round(nv))
    if (kind == 'date') {
      s$lo = as.character(min(v)); s$hi = as.character(max(v))
    } else {
      s$lo = min(nv); s$hi = max(nv); s$mean = mean(nv)
    }
  } else s$int = TRUE
  if (length(u) <= 1000L) {
    s$vals = I(if (kind == 'num') sort(u) else sort(as.character(u)))
  } else if (kind == 'date') {  # the slider steps through evenly spaced labels
    u = sort(as.character(u))
    s$vals = I(u[unique(round(seq(1, length(u), length.out = 1000)))])
  }
  bar = rep(-1L, length(x)); n = 0L
  if (!length(v)) {
    # no bars
  } else if (length(nv) == length(v) && kind != 'mix') {
    n = min(10L, length(u)); lo = min(nv); hi = max(nv)
    b = pmin(n - 1, floor((num - lo) / (if (hi > lo) hi - lo else 1) * n))
    bar = ifelse(is.na(num), -1L, as.integer(b))
  } else if (length(u) <= length(v) / 2) {
    key = as.character(tx)
    cnt = tabulate(match(key[!is.na(key)], as.character(u)), length(u))
    o = order(-cnt)  # stable: ties keep first-appearance order
    top = utils::head(o, 5)
    s$top = unname(lapply(top, function(i) list(as.character(u[i]), cnt[i])))
    n = length(u)
    bar = ifelse(is.na(key), -1L, match(key, as.character(u)[o]) - 1L)
  }
  s$bins = I(tabulate(bar + 1L, n))
  list(sketch = s, bar = bar, n = n)
}

# The JSON for one request: `q` holds the query parameters (see lt-server.js)
server_response = function(S, query) {
  q = as.list(query)
  data = S$data; n = nrow(data)
  keep = rep(TRUE, n)
  for (l in strsplit(q[['f']] %||% '', '\n', fixed = TRUE)[[1]]) {
    i = regexpr('\t', l, fixed = TRUE)
    c = substr(l, 1, i - 1)
    if (i > 0 && c %in% names(data))
      keep = keep & term_keep(substring(l, i + 1), list(S$tx[[c]]))
  }
  term = q[['t']] %||% ''
  cs = intersect(strsplit(q[['c']] %||% '', '\n', fixed = TRUE)[[1]], names(data))
  if (term != '' && length(cs)) keep = keep & term_keep(term, S$tx[cs])
  idx = server_order(which(keep), S$tx, strsplit(q[['s']] %||% '', '\n', fixed = TRUE)[[1]])
  total = length(idx)
  size = as.integer(q[['n']] %||% 0L); page = as.integer(q[['p']] %||% 0L)
  if (size > 0L) {
    page = max(0L, min(page, (total - 1L) %/% size))
    idx = idx[seq_len(size) + page * size]
    idx = idx[!is.na(idx)]
  } else page = 0L
  out = data[idx, , drop = FALSE]
  for (c in names(out)) if (inherits(out[[c]], 'Date') || is.factor(out[[c]]))
    out[[c]] = as.character(out[[c]])
  for (c in S$times) out[[c]] = format(out[[c]], '%Y-%m-%dT%H:%M:%SZ', tz = 'UTC')
  r = list(n = total, page = page, rows = length(idx), data = lapply(as.list(out), I))
  if (total < n) r$prof = lapply(S$bar, function(b)
    I(tabulate(b[which(keep)] + 1L, attr(b, 'n'))))
  xfun::tojson(r)
}

# Everything the app needs, computed once
server_state = function(x) {
  d = x$data
  tx = lapply(d, txt_col)
  sk = Map(col_sketch, d, tx)
  bar = lapply(sk, function(s) structure(s$bar, n = s$n))
  list(
    data = d, tx = tx, bar = Filter(function(b) attr(b, 'n') > 0, bar),
    sketch = lapply(sk, `[[`, 'sketch'),
    times = names(d)[vapply(d, inherits, NA, 'POSIXt')]
  )
}

# Row-indexed features can't follow rows that live on a server
check_server = function(x) {
  bad = vapply(x$ops, function(op) op$type %in% c('row_group', 'indent', 'group_order') ||
    (op$type %in% c('style', 'footnote') && !is.null(op$rows)), NA)
  if (any(bad) || !is.null(x$row_group))
    stop('server mode does not support row groups, indentation, or row-specific styles and footnotes')
  if (!is.null(x$interactive$detail) && inherits(x$interactive$detail, 'JS_LITERAL'))
    warning('a JavaScript row detail sees only the current page in server mode')
}

#' Serve a table from R, for data too big for the browser
#'
#' Show an interactive table whose rows stay in the R session. A local web app
#' (see [xfun::new_app()]) holds the data, and the browser asks it for just the
#' rows of the current page whenever the sort, filters, search, or page change,
#' so tables of millions of rows stay responsive. Everything [lt_interactive()]
#' offers works, with these differences:
#'
#' - Filter and search expressions (e.g., `x > 5`, `x != "A"`) are evaluated in
#'   R instead of JavaScript, so they must be R-compatible; the common ones, and
#'   everything the filter widgets write, work in both. Missing values never
#'   pass an expression unless it is negated.
#' - Substring search and filters match the underlying values, not the
#'   formatted text.
#' - Column profiles and filter choices come from the whole data, computed once
#'   when the app starts. Plots in cells ([lt_sparkline()], [lt_errorbar()],
#'   etc.) scale to the current page.
#' - Row groups, indentation, and row-specific styles and footnotes are not
#'   supported, and neither are external filter predicates.
#' - The CSV download fetches every row of the view.
#'
#' The app keeps serving while the R session is alive (until [xfun::stop_app()]).
#'
#' @param x An `lt_tbl` object, typically made by [lt_viewer()] or
#'   [lt_interactive()]; it is made interactive with the defaults if not yet.
#' @param name,... The app name and other arguments passed to
#'   [xfun::new_app()], such as `open = FALSE`.
#' @return The app URL, invisibly.
#' @export
#' @examples
#' if (interactive()) lt_serve(lt_viewer(iris))
lt_serve = function(x, name = 'lt-server', ...) {
  if (is.null(x$interactive)) x = lt_interactive(x)
  check_server(x)
  S = server_state(x)
  sizes = server_sizes(x$interactive$pager)
  x$interactive$pager = I(sizes)
  x$interactive$server = drop_null(list(
    url = 'data', n = nrow(S$data), times = if (length(S$times)) I(S$times),
    cols = S$sketch
  ))
  x$data = utils::head(S$data, sizes[1])
  html = view_html(x)
  xfun::new_app(name, function(path, query, ...) {
    if (path != 'data') return(list(payload = html))
    tryCatch(
      list(payload = server_response(S, query), `content-type` = 'application/json'),
      error = function(e) list(payload = conditionMessage(e), `status code` = 400L)
    )
  }, ...)
}
