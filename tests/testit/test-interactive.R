d = data.frame(x = 1:3, y = c("b", "a", "c"))

# A marker occurring exactly once in each asset, so it can be counted as well
# as looked for. The bare name of a class or a file is not enough: the CSS class
# names appear in the extension's script too, and `lt-interactive` appears in a
# comment inside core lt.js.
ext_css = '[.]lti-sortable \\{'; ext_js = 'LT[.]plugins[.]interactive = \\{'
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

assert("the extension follows the asset kind it belongs to", {
  x = lt(d) |> lt_interactive()
  # stylesheet only
  html = format(x, assets = 'css')
  (grepl(core_css, html) %==% TRUE)
  (grepl(ext_css, html) %==% TRUE)
  (grepl(ext_js, html) %==% FALSE)
  # script only
  html = format(x, assets = 'js')
  (grepl(core_js, html) %==% TRUE)
  (grepl(ext_js, html) %==% TRUE)
  (grepl(ext_css, html) %==% FALSE)
  # neither: the spec block alone
  html = format(x, assets = FALSE)
  (grepl(ext_css, html) %==% FALSE)
  (grepl(ext_js, html) %==% FALSE)
  (grepl('LT[.]q', html) %==% TRUE)
})

assert("the filter and pagination options reach the client spec", {
  # assets aside, format() emits the spec the runtime reads
  json = format(lt(d) |> lt_interactive(filter = 'y', pager = c(20, 5)), assets = FALSE)
  # a column vector boxes just those columns: each maps to `true` under `cols`
  (grepl('"filter": \\{\\s*"cols": \\{\\s*"y": true', json) %==% TRUE)
  # the page sizes keep the given order: the first one is the initial size
  (grepl('"pager": \\[20, 5\\]', json) %==% TRUE)
  # a single size still serializes as an array
  (grepl('"pager": \\[5\\]', format(lt(d) |> lt_interactive(pager = 5),
                                      assets = FALSE)) %==% TRUE)
  # Inf (every row on one page) travels as 0, which the runtime reads as such
  (grepl('"pager": \\[5, 0\\]', format(lt(d) |> lt_interactive(pager = c(5, Inf)),
                                         assets = FALSE)) %==% TRUE)
  # filtering every column needs no column list: just a default box
  (grepl('"filter": \\{\\s*"default": true\\s*\\}',
         format(lt(d) |> lt_interactive(filter = TRUE), assets = FALSE)) %==% TRUE)
  # paging is on by default; filtering is not
  json = format(lt(d) |> lt_interactive(), assets = FALSE)
  (grepl('"pager": \\[10, 25, 50, 100\\]', json) %==% TRUE)
  (grepl('filter', json) %==% FALSE)
  # both can be turned off
  json = format(lt(d) |> lt_interactive(pager = FALSE), assets = FALSE)
  (grepl('filter|pager', json) %==% FALSE)
})

assert("a default sort reaches the client spec as ordered name keys", {
  # the names travel as-is, keeping the '-' prefix; the client parses it
  json = format(lt(d) |> lt_interactive(sort = c('x', '-y')), assets = FALSE)
  (grepl('"sort": \\["x", "-y"\\]', json) %==% TRUE)
  # a one-sided formula is an equivalent way to spell the same keys
  (grepl('"sort": \\["x", "-y"\\]',
         format(lt(d) |> lt_interactive(sort = ~ x + -y), assets = FALSE)) %==% TRUE)
  (grepl('"sort": \\["x", "-y"\\]',
         format(lt(d) |> lt_interactive(sort = ~ x - y), assets = FALSE)) %==% TRUE)
  # a logical still passes through unchanged (enable or disable click-to-sort)
  (grepl('"sort": true', format(lt(d) |> lt_interactive(), assets = FALSE)) %==% TRUE)
  (grepl('"sort": false',
         format(lt(d) |> lt_interactive(sort = FALSE), assets = FALSE)) %==% TRUE)
})

assert("detail = column names resolves to a name array; js() stays verbatim", {
  # a formula / character vector of columns becomes a plain name array for the
  # runtime to build a one-row detail table from
  json = format(lt(d) |> lt_interactive(detail = ~ x + y), assets = FALSE)
  (grepl('"detail": ["x", "y"]', json, fixed = TRUE) %==% TRUE)
  json = format(lt(d) |> lt_interactive(detail = c('x', 'y')), assets = FALSE)
  (grepl('"detail": ["x", "y"]', json, fixed = TRUE) %==% TRUE)
  # a js() callback is emitted verbatim (unquoted), not as a string
  json = format(
    lt(d) |> lt_interactive(detail = js('(r, i, d) => ({})')), assets = FALSE
  )
  (grepl('"detail": (r, i, d) => ({})', json, fixed = TRUE) %==% TRUE)
})

count = function(p, x) sum(gregexpr(p, x)[[1]] > 0)

# Emulate a document: knit the tables in order, after clearing the flags that
# knit_print() uses to dedup assets (knitr resets them between real knits).
knit_doc = function(...) {
  for (f in c(.knit_flag, .int_flag))
    knitr::opts_knit$set(stats::setNames(list(NULL), f))
  paste(unlist(lapply(list(...), knit_print.lt_tbl)), collapse = '\n')
}

if (xfun::loadable('knitr'))
  assert("knit_print emits the extension once, for the first interactive table", {
    int = lt(d) |> lt_interactive(); static = lt(d)

    html = knit_doc(int, int)
    (count(ext_css, html) %==% 1L)
    (count(ext_js, html) %==% 1L)
    (count(core_js, html) %==% 1L)

    # a static table first: the core runtime is already out by the time the
    # extension is needed, and it still has to load after it
    html = knit_doc(static, int)
    (count(ext_css, html) %==% 1L)
    (count(ext_js, html) %==% 1L)
    (count(core_js, html) %==% 1L)
    (regexpr(ext_js, html) > regexpr(core_js, html))

    # a document with no interactive table never loads the extension
    (count(ext_js, knit_doc(static, static)) %==% 0L)
  })

assert("record_print emits the linked extension for an interactive table", {
  html = paste(unlist(record_print.lt_tbl(lt(d) |> lt_interactive())), collapse = '\n')
  (grepl('lt-interactive[^"]*[.]css', html) %==% TRUE)
  (grepl('lt-interactive[^"]*[.]js', html) %==% TRUE)
  html = paste(unlist(record_print.lt_tbl(lt(d))), collapse = '\n')
  (grepl('lt-interactive', html) %==% FALSE)
})
