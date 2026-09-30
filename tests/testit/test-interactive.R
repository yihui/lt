d = data.frame(x = 1:3, y = c("b", "a", "c"))

# Markers unique to each asset. `lt-interactive` alone is not enough: it also
# appears in a comment inside core lt.js.
ext_css = 'lti-search'; ext_js = 'LT\\.plugins\\.interactive'
core_css = '[.]lt-wrap \\{'; core_js = 'root[.]LT = \\{'

assert("the interactive extension is included only for a table that opts in", {
  html = format(lt(d) |> lt_interactive())
  (grepl(ext_css, html) %==% TRUE)
  (grepl(ext_js, html) %==% TRUE)
  html = format(lt(d))
  (grepl(ext_css, html) %==% FALSE)
  (grepl(ext_js, html) %==% FALSE)
})

assert("the linked form loads the extension after the core runtime", {
  html = format(lt(d) |> lt_interactive(), inline_assets = FALSE)
  (grepl('<link rel="stylesheet" href="[^"]*lt-interactive[^"]*">', html) %==% TRUE)
  # the plugin registers itself on the LT global, so core must execute first
  src = regmatches(html, gregexpr('<script src="[^"]+"', html))[[1]]
  (length(src) %==% 2L)
  (grepl('lt-interactive', src) %==% c(FALSE, TRUE))
})

assert("assets selects which pieces to emit, so a document can dedup them", {
  x = lt(d) |> lt_interactive()
  # a later interactive table, in a document that already emitted the runtime
  html = format(x, assets = 'interactive')
  (grepl(ext_css, html) %==% TRUE)
  (grepl(ext_js, html) %==% TRUE)
  (grepl(core_css, html) %==% FALSE)
  (grepl(core_js, html) %==% FALSE)
  # the runtime without the extension, for a document whose first table is
  # static and whose second one is interactive
  html = format(x, assets = c('css', 'js'))
  (grepl(core_js, html) %==% TRUE)
  (grepl(ext_js, html) %==% FALSE)
  # nothing at all
  (grepl('<script', format(x, assets = FALSE)) %==% TRUE)  # only the spec block
  (grepl(ext_js, format(x, assets = FALSE)) %==% FALSE)
  # asking for the extension on a static table is a no-op
  (grepl(ext_js, format(lt(d), assets = 'interactive')) %==% FALSE)
})

assert("record_print emits the linked extension for an interactive table", {
  html = paste(unlist(record_print.lt_tbl(lt(d) |> lt_interactive())), collapse = '\n')
  (grepl('lt-interactive[^"]*[.]css', html) %==% TRUE)
  (grepl('lt-interactive[^"]*[.]js', html) %==% TRUE)
  html = paste(unlist(record_print.lt_tbl(lt(d))), collapse = '\n')
  (grepl('lt-interactive', html) %==% FALSE)
})
