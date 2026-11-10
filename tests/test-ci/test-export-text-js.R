# CSV/RTF text of a table built in headless Chromium (no Node.js) matches the
# Node.js build.

x = lt(data.frame(g.a = c('x{y}', 'é,z'), g.b = c(1.5, 22))) |>
  lt_header('Title') |> lt_spanner('G', c('g.a', 'g.b')) |> lt_note('A note')

assert("browser and Node builds of CSV and RTF text agree", {
  for (fmt in c('csv', 'rtf')) {
    node = lt_text(x, fmt, node = TRUE)
    browser = lt_text(x, fmt, node = FALSE)
    (browser %==% node)
  }
})

assert("lt_export(method = 'browser') writes the same CSV text as Node.js", {
  f = tempfile(fileext = '.csv')
  on.exit(unlink(f), add = TRUE)
  lt_export(x, f, method = 'browser')
  (xfun::read_utf8(f) %==% lt_text(x, 'csv', node = TRUE))
})
