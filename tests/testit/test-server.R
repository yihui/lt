library(testit)

d = data.frame(
  a = c(1, 5, NA, 9), g = c('x', 'y', 'x', NA), d = as.Date('2024-01-01') + 0:3,
  t = as.POSIXct('2024-01-01 10:00:00', tz = 'UTC') + 3600 * (0:3)
)
S = server_state(lt(d))
# a request: filters as leaves `col = term`, ANDed
req = function(..., where = NULL, sort = NULL, size = 0, page = 0, cols = list()) {
  f = list(...)
  w = c(unname(Map(function(c, t) list(col = c, term = t), names(f), f)), where)
  list(q = jsonlite::toJSON(list(
    where = if (length(w)) list(op = 'and', items = w), sort = sort, size = size,
    page = page, cols = cols
  ), auto_unbox = TRUE, null = 'null'))
}
resp = function(...) jsonlite::fromJSON(server_response(S, req(...)), simplifyVector = FALSE)
rows = function(...) as.numeric(unlist(lapply(resp(...)$data$a, function(v) if (is.null(v)) NA else v)))
asc = list(list(col = 'a', dir = 'asc')); desc = list(list(col = 'a', dir = 'desc'))
any_col = function(t) list(list(col = NULL, term = t))

assert('filter expressions written by the widgets are evaluated in R', {
  (rows(a = 'x >= 2 && x <= 9') %==% c(5, 9))
  (rows(g = '["x"].includes(x)') %==% c(1, NA))
  (rows(g = '["x",null].includes(x ?? null)') %==% c(1, NA, 9))
  (rows(g = '[null].includes(x ?? null)') %==% 9)
  (rows(g = 'x == "y"') %==% 5)
  (rows(a = 'x > 0', a = 'x < 9') %==% c(1, 5))
  (rows(g = 'x == null') %==% 9)
  (rows(d = 'x >= "2024-01-03"') %==% c(NA, 9))
})

assert('a negated expression keeps missing values, others drop them', {
  (rows(a = 'x != 5') %==% c(1, NA, 9))
  (rows(a = 'x > 0') %==% c(1, 5, 9))
})

assert('unsafe expressions are ignored, and fall back to substring matching', {
  (is.null(js_expr('system("ls") == x')))
  (rows(g = 'x; y') %==% numeric())
})

assert('conditions combine as trees; search covers the visible columns', {
  (rows(where = list(list(op = 'or', items = list(
    list(col = 'a', term = 'x == 1'), list(col = 'g', term = 'y'))))) %==% c(1, 5))
  (rows(where = any_col('y'), cols = list('a', 'g')) %==% 5)
  (rows(where = any_col('!y'), cols = list('g')) %==% c(1, NA, 9))
  (rows(where = any_col('y'), cols = list('a')) %==% numeric())
  (rows(sort = asc) %==% c(1, 5, 9, NA))
  (rows(sort = desc) %==% c(9, 5, 1, NA))
})

assert('paging clamps the page and reports the total', {
  r = resp(size = 3, page = 9)
  (r$n %==% 4L)
  (r$page %==% 1L)
  (length(r$data$a) %==% 1L)
})

assert('profile counts follow the filter; date-times travel as ISO text', {
  r = resp(a = 'x > 4')
  (sum(unlist(r$prof$a)) %==% 2L)
  (r$data$t[[1]] %==% '2024-01-01T11:00:00Z')
})

assert('the column sketch carries what filter widgets need', {
  s = S$sketch
  (s$a$lo %==% 1)
  (s$a$hi %==% 9)
  (s$a$na %==% 1L)
  (s$g$vals %==% I(c('x', 'y')))
  (s$d$lo %==% '2024-01-01')
})

assert('lt_serve() rejects row-indexed features', {
  (has_error(check_server(lt(d) |> lt_indent(1))))
  (has_error(check_server(lt(d) |> lt_style('a', rows = 1, bold = TRUE))))
})

assert('lt_serve() adds the data URL to the spec and keeps an lt_tbl', {
  x = lt_serve(lt(d), url = 'http://localhost/data')
  (inherits(x, 'lt_tbl'))
  (x$interactive$data_url %==% 'http://localhost/data')
  (nrow(x$data) %==% 0L)
})

assert('case-insensitive text conditions from plain-language queries work', {
  (rows(g = 'String(x).toLowerCase() == "x"') %==% c(1, NA))
  (rows(g = '!String(x).toLowerCase().includes("y")') %==% c(1, NA, 9))
  (rows(g = 'String(x).toLowerCase() != "x"') %==% c(5, 9))
})
