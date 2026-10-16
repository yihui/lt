d = data.frame(x = 1:3, y = c("b", "a", "c"))

# A marker occurring exactly once in each asset, so it can be counted as well
# as looked for. The bare name of a class or a file is not enough: the CSS class
# names appear in the extension's script too, and `lt-interactive` appears in a
# comment inside core lt.js.
ext_css = '[.]lti-sort \\{'; ext_js = 'LT[.]plugins[.]interactive = \\{'
core_css = '[.]lt-wrap \\{'; core_js = 'root[.]LT = \\{'

assert("the interactive extension is included only for a table that opts in", {
  html = format(lt(d) |> lt_interactive())
  (has_match(html, ext_css))
  (has_match(html, ext_js))
  html = format(lt(d))
  (has_match(html, !ext_css))
  (has_match(html, !ext_js))
})

assert("the linked form loads the extension after the core runtime", {
  html = format(lt(d) |> lt_interactive(), inline_assets = FALSE)
  (has_match(html, '<link rel="stylesheet" href="[^"]*lt-interactive[^"]*">'))
  # the plugin registers itself on the LT global, so core must execute first
  src = regmatches(html, gregexpr('<script src="[^"]+"', html))[[1]]
  (length(src) %==% 2L)
  (grepl('lt-interactive', src) %==% c(FALSE, TRUE))
})

assert("the extension follows the asset kind it belongs to", {
  x = lt(d) |> lt_interactive()
  # stylesheet only
  html = format(x, assets = 'css')
  (has_match(html, core_css))
  (has_match(html, ext_css))
  (has_match(html, !ext_js))
  # script only
  html = format(x, assets = 'js')
  (has_match(html, core_js))
  (has_match(html, ext_js))
  (has_match(html, !ext_css))
  # neither: the spec block alone
  html = format(x, assets = FALSE)
  (has_match(html, !ext_css))
  (has_match(html, !ext_js))
  (has_match(html, 'LT[.]q'))
})

assert("the filter and pagination options reach the client spec", {
  # assets aside, format() emits the spec the runtime reads
  json = format(lt(d) |> lt_interactive(filter = 'y', pager = c(20, 5)), assets = FALSE)
  # a column vector boxes just those columns: each maps to `true` under `cols`
  (has_match(json, '"filter": \\{\\s*"cols": \\{\\s*"y": true'))
  # the page sizes keep the given order: the first one is the initial size
  (has_match(json, '"pager": \\[20, 5\\]'))
  # a single size still serializes as an array
  (has_match(format(lt(d) |> lt_interactive(pager = 5), assets = FALSE),
             '"pager": \\[5\\]'))
  # Inf (every row on one page) travels as 0, which the runtime reads as such
  (has_match(format(lt(d) |> lt_interactive(pager = c(5, Inf)), assets = FALSE),
             '"pager": \\[5, 0\\]'))
  # filtering every column needs no column list: just a default box
  (has_match(format(lt(d) |> lt_interactive(filter = TRUE), assets = FALSE),
             '"filter": \\{\\s*"default": true\\s*\\}'))
  # paging is on by default; filtering is not
  json = format(lt(d) |> lt_interactive(), assets = FALSE)
  (has_match(json, '"pager": \\[10, 25, 50, 100\\]'))
  (has_match(json, !'filter'))
  # both can be turned off
  json = format(lt(d) |> lt_interactive(pager = FALSE), assets = FALSE)
  (has_match(json, !'filter|pager'))
})

assert("a typed filter spec reaches the client with its options", {
  # a checklist spec keeps its type and label, reshapes `choices` to {value,label}
  # objects, and keeps a scalar `selected` as a JSON array (so the client seeds it)
  json = format(lt(d) |> lt_interactive(filter = list(
    y = list(type = "checklist", label = "Y", choices = c("a", "b"), selected = "a")
  )), assets = FALSE)
  (has_match(json, '"type": "checklist"'))
  (has_match(json, '"label": "Y"'))
  (has_match(json, '"choices": \\[\\s*\\{\\s*"value": "a",\\s*"label": "a"'))
  (has_match(json, '"selected": \\["a"\\]'))
})

assert("a default sort reaches the client spec as ordered name keys", {
  # the names travel as-is, keeping the '-' prefix; the client parses it
  json = format(lt(d) |> lt_interactive(sort = c('x', '-y')), assets = FALSE)
  (has_match(json, '"sort": \\["x", "-y"\\]'))
  # a one-sided formula is an equivalent way to spell the same keys
  (has_match(format(lt(d) |> lt_interactive(sort = ~ x + -y), assets = FALSE),
             '"sort": \\["x", "-y"\\]'))
  (has_match(format(lt(d) |> lt_interactive(sort = ~ x - y), assets = FALSE),
             '"sort": \\["x", "-y"\\]'))
  # a logical still passes through unchanged (enable or disable click-to-sort)
  (has_match(format(lt(d) |> lt_interactive(), assets = FALSE), '"sort": true'))
  (has_match(format(lt(d) |> lt_interactive(sort = FALSE), assets = FALSE),
             '"sort": false'))
})

assert("download reaches the client spec as true or a file name, else absent", {
  # TRUE enables the button with no file name of its own (the client defaults it)
  (has_match(format(lt(d) |> lt_interactive(download = TRUE), assets = FALSE),
             '"download": true'))
  # a string sets the file name, kept verbatim
  (has_match(format(lt(d) |> lt_interactive(download = 'cars.csv'), assets = FALSE),
             I('"download": "cars.csv"')))
  # off by default, and FALSE/NULL emit nothing
  (has_match(format(lt(d) |> lt_interactive(), assets = FALSE), !'download'))
  (has_match(format(lt(d) |> lt_interactive(download = FALSE), assets = FALSE),
             !'download'))
  # the shaper drops a disabled download so no key is serialized
  (download_opt(NULL) %==% NULL)
  (download_opt(FALSE) %==% NULL)
  # TRUE and a bare file name pass through unchanged
  (download_opt(TRUE) %==% TRUE)
  (download_opt('cars.csv') %==% 'cars.csv')
  # raw mode serializes an object carrying the mode (and file, if given)
  (download_opt(list(file = 'cars.csv', mode = 'raw')) %==%
     list(file = 'cars.csv', mode = 'raw'))
  # raw mode with the default file name omits the file slot
  (download_opt(list(mode = 'raw')) %==% list(mode = 'raw'))
  # the display mode stays implicit: a bare string (or TRUE), never a mode key
  (download_opt(list(file = 'cars.csv', mode = 'display')) %==% 'cars.csv')
  (download_opt(list(mode = 'display')) %==% TRUE)
})

assert("detail = column names resolves to a name array; js() stays verbatim", {
  # a formula / character vector of columns becomes a plain name array for the
  # runtime to build a one-row detail table from
  json = format(lt(d) |> lt_interactive(detail = ~ x + y), assets = FALSE)
  (has_match(json, I('"detail": ["x", "y"]')))
  json = format(lt(d) |> lt_interactive(detail = c('x', 'y')), assets = FALSE)
  (has_match(json, I('"detail": ["x", "y"]')))
  # a js() callback is emitted verbatim (unquoted), not as a string
  json = format(
    lt(d) |> lt_interactive(detail = js('(r, i, d) => ({})')), assets = FALSE
  )
  (has_match(json, I('"detail": (r, i, d) => ({})')))
})

count = function(p, x) sum(gregexpr(p, x)[[1]] > 0)

# Emulate a document: knit the tables in order, after clearing the flags that
# knit_print() uses to dedup assets (knitr resets them between real knits).
knit_doc = function(...) {
  for (f in c(.knit_flag, .int_flag))
    knitr::opts_knit$set(set_names(list(NULL), f))
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
  (has_match(html, 'lt-interactive[^"]*[.]css'))
  (has_match(html, 'lt-interactive[^"]*[.]js'))
  html = paste(unlist(record_print.lt_tbl(lt(d))), collapse = '\n')
  (has_match(html, !'lt-interactive'))
})
