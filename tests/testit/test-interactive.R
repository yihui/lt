d = data.frame(x = 1:3, y = c("b", "a", "c"))

# Marker occurring exactly once in each asset, so it can be counted as well
# as looked for. Bare class or file name is not enough: CSS class names
# appear in extension's script too, and `lt-interactive` appears in a
# comment inside core lt.js. Optional spaces let it match the minified assets
# shipped in the built package too.
ext_css = '[.]lti-sort ?\\{'; ext_js = '[.]plugins[.]interactive ?= ?\\{'
core_css = '[.]lt-wrap ?\\{'; core_js = '[.]LT ?= ?\\{'

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
  # plugin registers on LT global, so core must execute first
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
  # assets aside, format() emits spec runtime reads
  json = format(lt(d) |> lt_interactive(filter = 'y', pager = c(20, 5)), assets = FALSE)
  # column vector boxes just those columns: each maps to `true` under `cols`
  (has_match(json, '"filter": \\{\\s*"cols": \\{\\s*"y": true'))
  # page sizes keep given order: first is initial size
  (has_match(json, I('"pager": [20, 5]')))
  # single size still serializes as array
  (has_match(format(lt(d) |> lt_interactive(pager = 5), assets = FALSE), I('"pager": [5]')))
  # Inf (every row on one page) travels as 0, which runtime reads as such
  (has_match(format(lt(d) |> lt_interactive(pager = c(5, Inf)), assets = FALSE), I('"pager": [5, 0]')))
  # filtering every column needs no column list: just default box
  (has_match(format(lt(d) |> lt_interactive(filter = TRUE), assets = FALSE), '"filter": \\{\\s*"default": true\\s*\\}'))
  # paging is on by default; filtering is not
  json = format(lt(d) |> lt_interactive(), assets = FALSE)
  (has_match(json, I('"pager": [10, 25, 50, 100]')))
  (has_match(json, !'filter'))
  # both can be turned off
  json = format(lt(d) |> lt_interactive(pager = FALSE), assets = FALSE)
  (has_match(json, !'filter|pager'))
})

assert("filter = 'auto' is a default spec, not a column name", {
  json = format(lt(d) |> lt_interactive(filter = 'auto'), assets = FALSE)
  (has_match(json, '"default": \\{\\s*"type": "auto"'))
  (has_match(json, !'"cols"'))
})

assert("a column set to FALSE gets no filter spec", {
  json = format(lt(d) |> lt_interactive(filter = list(TRUE, y = FALSE)), assets = FALSE)
  (has_match(json, '"y": false'))
  (has_match(json, '"default": true'))
})

assert("a typed filter spec reaches the client with its options", {
  # checklist spec keeps type and label, reshapes `choices` to {value,label}
  # objects, keeps scalar `selected` as JSON array (so client seeds it)
  json = format(lt(d) |> lt_interactive(filter = list(
    y = list(type = "checklist", label = "Y", choices = c("a", "b"), selected = "a")
  )), assets = FALSE)
  (has_match(json, '"type": "checklist"'))
  (has_match(json, '"label": "Y"'))
  (has_match(json, '"choices": \\[\\s*\\{\\s*"value": "a",\\s*"label": "a"'))
  (has_match(json, I('"selected": ["a"]')))
})

assert("a default sort reaches the client spec as ordered name keys", {
  # names travel as-is, keeping '-' prefix; client parses it
  json = format(lt(d) |> lt_interactive(sort = c('x', '-y')), assets = FALSE)
  (has_match(json, I('"sort": ["x", "-y"]')))
  # one-sided formula is equivalent way to spell same keys
  (has_match(format(lt(d) |> lt_interactive(sort = ~ x + -y), assets = FALSE), I('"sort": ["x", "-y"]')))
  (has_match(format(lt(d) |> lt_interactive(sort = ~ x - y), assets = FALSE), I('"sort": ["x", "-y"]')))
  # logical passes through unchanged (enable/disable click-to-sort)
  (has_match(format(lt(d) |> lt_interactive(), assets = FALSE), '"sort": true'))
  (has_match(format(lt(d) |> lt_interactive(sort = FALSE), assets = FALSE), '"sort": false'))
})

assert("download reaches the client spec as true or a file name, else absent", {
  # TRUE enables button with no file name (client defaults it)
  (has_match(format(lt(d) |> lt_interactive(download = TRUE), assets = FALSE), '"download": true'))
  # string sets file name, kept verbatim
  (has_match(format(lt(d) |> lt_interactive(download = 'cars.csv'), assets = FALSE), I('"download": "cars.csv"')))
  # off by default, and FALSE/NULL emit nothing
  (has_match(format(lt(d) |> lt_interactive(), assets = FALSE), !'download'))
  (has_match(format(lt(d) |> lt_interactive(download = FALSE), assets = FALSE), !'download'))
  # shaper drops disabled download so no key serialized
  (download_opt(NULL) %==% NULL)
  (download_opt(FALSE) %==% NULL)
  # TRUE and bare file name pass through unchanged
  (download_opt(TRUE) %==% TRUE)
  (download_opt('cars.csv') %==% 'cars.csv')
  # raw mode serializes object carrying mode (and file, if given)
  (download_opt(list(file = 'cars.csv', mode = 'raw')) %==%
     list(file = 'cars.csv', mode = 'raw'))
  # raw mode with default file name omits file slot
  (download_opt(list(mode = 'raw')) %==% list(mode = 'raw'))
  # display mode stays implicit: bare string (or TRUE), never a mode key
  (download_opt(list(file = 'cars.csv', mode = 'display')) %==% 'cars.csv')
  (download_opt(list(mode = 'display')) %==% TRUE)
})

assert("detail = column names resolves to a name array", {
  # formula / character vector of columns becomes plain name array for
  # runtime to build one-row detail table from
  json = format(lt(d) |> lt_interactive(detail = ~ x + y), assets = FALSE)
  (has_match(json, I('"detail": ["x", "y"]')))
  json = format(lt(d) |> lt_interactive(detail = c('x', 'y')), assets = FALSE)
  (has_match(json, I('"detail": ["x", "y"]')))
})

count = function(p, x) sum(gregexpr(p, x)[[1]] > 0)

# Emulate a document: knit tables in order, after clearing flags
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

    # static table first: core runtime already out by time extension is
    # needed; extension must still load after it
    html = knit_doc(static, int)
    (count(ext_css, html) %==% 1L)
    (count(ext_js, html) %==% 1L)
    (count(core_js, html) %==% 1L)
    (regexpr(ext_js, html) > regexpr(core_js, html))

    # document with no interactive table never loads extension
    (count(ext_js, knit_doc(static, static)) %==% 0L)
  })

assert("record_print emits the linked extension for an interactive table", {
  html = paste(unlist(record_print.lt_tbl(lt(d) |> lt_interactive())), collapse = '\n')
  (has_match(html, 'lt-interactive[^"]*[.]css'))
  (has_match(html, 'lt-interactive[^"]*[.]js'))
  html = paste(unlist(record_print.lt_tbl(lt(d))), collapse = '\n')
  (has_match(html, !'lt-interactive'))
})
