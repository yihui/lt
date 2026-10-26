assert('view_lt() opens a data frame with column filters by default', {
  viewed = NULL
  f = tempfile(fileext = '.html')
  on.exit(unlink(f))
  path = view_lt(data.frame(x = 1:3), pager = FALSE,
    file = f, serve = FALSE, browser = function(url) viewed <<- url)
  html = paste(readLines(path, warn = FALSE), collapse = '\n')
  (identical(viewed, normalizePath(f)))
  (grepl('lt-interactive.js', html, fixed = TRUE))
  (grepl('"filter":\\s*\\{\\s*"default":\\s*true', html, perl = TRUE))
  (grepl('"pager"', html, fixed = TRUE) %==% FALSE)
})

assert('view_lt() preserves a formatted lt table', {
  viewed = NULL
  f = tempfile(fileext = '.html')
  on.exit(unlink(f))
  x = lt(data.frame(x = 1.234)) |>
    lt_header('Formatted table') |>
    lt_interactive(filter = FALSE, pager = FALSE)
  path = view_lt(x, file = f, serve = FALSE,
    browser = function(url) viewed <<- url)
  html = paste(readLines(path, warn = FALSE), collapse = '\n')
  (identical(viewed, normalizePath(f)))
  (grepl('Formatted table', html, fixed = TRUE))
  (grepl('lt-interactive.js', html, fixed = TRUE))
  (grepl('"filter":\\s*\\{\\s*"default":\\s*true', html, perl = TRUE) %==% FALSE)
  (grepl('"pager"', html, fixed = TRUE) %==% FALSE)
})

assert('view_lt() allows column filters to be disabled', {
  f = tempfile(fileext = '.html')
  on.exit(unlink(f))
  view_lt(data.frame(x = 1:3), filter = FALSE, file = f, serve = FALSE,
    browser = function(url) NULL)
  html = paste(readLines(f, warn = FALSE), collapse = '\n')
  (grepl('"filter":\\s*\\{\\s*"default":\\s*true', html, perl = TRUE) %==% FALSE)
})

assert('view_lt() sends a local HTTP URL to the browser callback by default', {
  viewed = NULL
  f = tempfile(fileext = '.html')
  on.exit({ xfun::stop_app('lt-test-view'); unlink(f) })
  url = view_lt(data.frame(x = 1:3), file = f, name = 'lt-test-view',
    wait = FALSE, browser = function(url) viewed <<- url)
  (identical(viewed, url))
  (startsWith(url, 'http://127.0.0.1:'))
  (endsWith(url, '/custom/lt-test-view/'))
  (file.exists(f))
})

assert('view_lt(open = FALSE) reports the URL without opening a browser', {
  viewed = FALSE
  f = tempfile(fileext = '.html')
  on.exit({ xfun::stop_app('lt-test-view'); unlink(f) })
  has_message(view_lt(data.frame(x = 1:3), file = f,
    name = 'lt-test-view', open = FALSE, wait = FALSE,
    browser = function(url) viewed <<- TRUE),
    message = 'lt table: http://127.0.0.1:', fixed = TRUE)
  (viewed %==% FALSE)
})

assert('view_lt() requires an HTML path', {
  has_error(view_lt(data.frame(x = 1), file = tempfile(fileext = '.png'),
    browser = function(url) NULL))
})
