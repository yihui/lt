# Embed a small example from examples/ as a child document: drop its YAML
# header and intro (everything before the first code chunk), the `library(lt)`
# line, the runtime-assets chunk (the JS chapter loads it once), and anything
# after an `<!-- end -->` marker. A link to the example's own page follows.
ex = function(name) {
  f = Sys.glob(sprintf('../examples/[0-9][0-9]-%s.Rmd', name))
  if (length(f) != 1) stop('found ', length(f), ' example(s) named ', name)
  x = xfun::read_utf8(f)
  x = x[seq(grep('^```', x)[1], length(x))]
  x = x[seq_len(min(c(length(x), grep('^<!-- end -->$', x) - 1)))]
  x = paste(x[x != 'library(lt)'], collapse = '\n')
  x = gsub('```\\{r assets.*?\n```\n', '', x)
  p = tempfile(fileext = '.Rmd')
  xfun::write_utf8(x, p)
  p
}
