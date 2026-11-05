library(testit)

assert('lt_viewer() tags column types and profiles each column', {
  x = lt_viewer(head(iris))
  (inherits(x, 'lt_tbl'))
  (!is.null(x$types))
  (x$interactive$profile %==% 'header')
  (lt_viewer(head(iris), profile = 'filter')$interactive$profile %==% 'filter')
})
