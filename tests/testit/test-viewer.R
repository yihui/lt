library(testit)

assert('lt_viewer() tags column types and profiles each column', {
  x = lt_viewer(head(iris))
  (inherits(x, 'lt_tbl'))
  (!is.null(x$types))
  (x$interactive$profile %==% 'header')
  (x$interactive$hide %==% TRUE)
  (lt_viewer(head(iris), profile = 'filter')$interactive$profile %==% 'filter')
})

assert('lt_viewer() captions the table with the data expression and its size', {
  x = lt_viewer(head(iris))
  (x$header$title %==% 'head(iris)')
  (x$header$subtitle %==% '6 rows, 5 columns')
  (is.null(lt_viewer(iris, title = NULL)$header$title))
})
