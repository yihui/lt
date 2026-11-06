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
  # case-insensitive text tests written by plain-language queries
  term = gsub(
    'String\\(x\\)\\.toLowerCase\\(\\)\\.includes\\(("(?:[^"\\\\]|\\\\.)*")\\)',
    'grepl(\\1, tolower(as.character(x)), fixed = TRUE)', term, perl = TRUE
  )
  term = gsub('String\\(x\\)\\.toLowerCase\\(\\)', 'tolower(as.character(x))', term)
  term = gsub('!==', '!=', gsub('===', '==', term, fixed = TRUE), fixed = TRUE)
  term = gsub('(!?)=\\s*null\\b', '\\1= NA_integer_', term)  # x == null
  e = tryCatch(parse(text = term, keep.source = FALSE), error = function(e) NULL)
  if (length(e) != 1L) return()
  e = e[[1]]
  ok = c(
    '(', '!', '==', '!=', '<', '>', '<=', '>=', '&', '|', '&&', '||', '+', '-',
    '*', '/', '%in%', 'c', 'is.na', 'nchar', 'tolower', 'toupper', 'grepl',
    'as.character', 'x',
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
    # JS compares text to a number numerically, so only a string literal (or a
    # test of missing values or set membership) keeps text as is
    numify = !grepl('"', term, fixed = TRUE) && !any(c('is.na', '%in%') %in% all.names(e))
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

# Rows kept by a filter tree: a leaf `{col, term}` (`col` null: any of columns
# `cs`) or `{op: "and" | "or", items}`
tree_keep = function(t, tx, cs) {
  if (!is.null(t$op))
    return(Reduce(if (t$op == 'and') `&` else `|`, lapply(t$items, tree_keep, tx, cs)))
  xs = tx[intersect(if (is.null(t$col)) cs else t$col, names(tx))]
  if (length(xs)) term_keep(t$term, xs) else rep(TRUE, length(tx[[1]]))
}

# Row order for sort keys `s` ("a:col" / "d:col"), nulls last
server_order = function(idx, tx, s) {
  s = Filter(function(k) k$col %in% names(tx), s)
  if (!length(s)) return(idx)
  dir = vapply(s, function(k) identical(k$dir, 'desc'), NA)
  keys = lapply(s, function(k) {
    k = tx[[k$col]][idx]
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

# Reads the JSON a browser's JSON.stringify() makes (objects -> named lists,
# arrays -> lists, null -> NULL): R source with the same shape, once the tokens
# are renamed, so R's parser does the work. Strings stay quoted tokens, and
# anything else must be a number or keyword, so no code can slip in.
parse_json = function(x) {
  tok = regmatches(x, gregexpr(
    '"(?:[^"\\\\]|\\\\.)*"|[{}\\[\\],:]|[^"{}\\[\\],:]+', x, perl = TRUE
  ))[[1]]
  lit = !grepl('^["{}\\[\\],:]', tok, perl = TRUE)
  tok[lit] = trimws(tok[lit])
  key = c(`{` = 'list(', `[` = 'list(', `}` = ')', `]` = ')', `:` = '=', true = 'TRUE',
          false = 'FALSE', null = 'NULL')
  i = match(tok, names(key))
  tok[!is.na(i)] = key[i[!is.na(i)]]
  if (!all(grepl('^(-?[0-9.]+([eE][-+]?[0-9]+)?)?$', tok[lit & is.na(i)])))
    stop('invalid JSON')
  eval(parse(text = paste(tok, collapse = ''), keep.source = FALSE), baseenv())
}

# The JSON for one request: `body` is the request JSON (see ?lt_serve)
server_response = function(S, body) {
  q = parse_json(body)
  data = S$data; n = nrow(data)
  keep = if (is.null(q$where)) rep(TRUE, n) else tree_keep(q$where, S$tx, unlist(q$cols))
  idx = server_order(which(keep), S$tx, q$sort)
  total = length(idx)
  size = as.integer(q$size %||% 0L); page = as.integer(q$page %||% 0L)
  if (size > 0L) {
    page = max(0L, min(page, (total - 1L) %/% size))
    idx = idx[seq_len(size) + page * size]
    idx = idx[!is.na(idx)]
  } else page = 0L
  out = data[idx, , drop = FALSE]
  # explicit conversions: CI's xfun (0.62) writes date-times as plain text, not ISO
  for (c in names(out)) {
    v = out[[c]]
    if (inherits(v, 'Date') || is.factor(v)) out[[c]] = as.character(v)
    else if (is.numeric(v)) out[[c]] = replace(v, !is.finite(v), NA)
  }
  for (c in S$times) out[[c]] = format(out[[c]], '%Y-%m-%dT%H:%M:%SZ', tz = 'UTC')
  r = list(n = total, page = page, data = lapply(as.list(out), I))
  if (total < n) r$prof = lapply(S$bar, function(b)
    I(tabulate(b[which(keep)] + 1L, attr(b, 'n'))))
  xfun::tojson(r, mode = 'json')
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

#' Serve the rows of an interactive table from a data server
#'
#' Make an interactive table fetch its rows from a URL instead of holding them
#' in the page, for data too big for the browser: whenever the sort, filters,
#' search, or page change, the browser asks the server for just the current
#' page. By default the rows of `x` are served by a local app built on
#' [xfun::new_app()] (until [xfun::stop_app()]); pass `url` to use your own
#' server instead. Row groups, indentation, and row-specific styles and
#' footnotes are not supported. See the examples in the package site for
#' details and the request/response format a custom server implements.
#'
#' @param x An `lt_tbl` object, typically made by [lt_viewer()] or
#'   [lt_interactive()]; it is made interactive with the defaults if not yet.
#' @param url The URL of a data server (absolute, or relative to the page). By
#'   default, a local app serving the rows of `x` is started; view the table by
#'   printing the result.
#' @param times,cols For a custom `url`: the date-time columns (names), and,
#'   optionally, a summary of each column (a named list) to draw profiles and
#'   filter widgets. The local app computes both from the data.
#' @param name,... For the local app: its name and other arguments passed to
#'   [xfun::new_app()].
#' @return `x`, with the data URL added.
#' @export
#' @examples
#' if (interactive()) lt_serve(lt_viewer(iris))
lt_serve = function(x, url = NULL, times = NULL, cols = NULL, name = 'lt-server', ...) {
  if (is.null(x$interactive)) x = lt_interactive(x)
  check_server(x)
  sizes = server_sizes(x$interactive$pager)
  x$interactive$pager = I(sizes)
  if (is.null(url)) {
    S = server_state(x)
    xfun::new_app(name, function(path, query, post, ...) tryCatch(
      list(
        payload = server_response(S, rawToChar(post)), `content-type` = 'application/json',
        headers = 'Access-Control-Allow-Origin: *'
      ),
      error = function(e) list(payload = conditionMessage(e), `status code` = 400L)
    ), open = FALSE, ...)
    # relative to the page shown by print() (served at /custom/lt/), so it also
    # works when 127.0.0.1 isn't the browser's own machine (remote sessions)
    url = sprintf('../%s/data', name)
    times = S$times; cols = S$sketch
  }
  x$interactive$data_url = url
  x$interactive$data_times = if (length(times)) I(times)
  x$interactive$data_cols = cols
  x$data = utils::head(x$data, 0)
  x
}
