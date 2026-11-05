library(testit)

d = data.frame(
  a = c(1, 5, NA, 9), g = c('x', 'y', 'x', NA), d = as.Date('2024-01-01') + 0:3,
  t = as.POSIXct('2024-01-01 10:00:00', tz = 'UTC') + 3600 * (0:3)
)
S = server_state(lt(d))
rows = function(...) {
  r = jsonlite::fromJSON(server_response(S, c(...)), simplifyVector = FALSE)
  as.numeric(unlist(lapply(r$data$a, function(v) if (is.null(v)) NA else v)))
}

assert('filter expressions written by the widgets are evaluated in R', {
  (rows(f = 'a\tx >= 2 && x <= 9') %==% c(5, 9))
  (rows(f = 'g\t["x"].includes(x)') %==% c(1, NA))
  (rows(f = 'g\t["x",null].includes(x ?? null)') %==% c(1, NA, 9))
  (rows(f = 'g\tx == "y"') %==% 5)
  (rows(f = 'a\tx > 0\na\tx < 9') %==% c(1, 5))
  (rows(f = 'g\tx == null') %==% 9)
  (rows(f = 'd\tx >= "2024-01-03"') %==% c(NA, 9))
})

assert('a negated expression keeps missing values, others drop them', {
  (rows(f = 'a\tx != 5') %==% c(1, NA, 9))
  (rows(f = 'a\tx > 0') %==% c(1, 5, 9))
})

assert('unsafe expressions are ignored, and fall back to substring matching', {
  (is.null(js_expr('system("ls") == x')))
  (rows(f = 'g\tx; y') %==% numeric())
})

assert('search matches any column; sort puts missing values last', {
  (rows(t = 'y', c = 'a\ng') %==% 5)
  (rows(t = '!y', c = 'g') %==% c(1, NA, 9))
  (rows(s = 'd:a') %==% c(9, 5, 1, NA))
})

assert('paging clamps the page and reports the total', {
  r = jsonlite::fromJSON(server_response(S, c(n = '3', p = '9')), simplifyVector = FALSE)
  (r$n %==% 4L)
  (r$page %==% 1L)
  (r$rows %==% 1L)
})

assert('profile counts follow the filter; date-times travel as ISO text', {
  r = jsonlite::fromJSON(server_response(S, c(f = 'a\tx > 4')), simplifyVector = FALSE)
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
