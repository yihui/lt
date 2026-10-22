d = data.frame(x = 1:2, y = c("a", "b"))
x = lt(d)

assert("format() returns HTML with script tags", {
  (has_match(format(x), "<script>.*</script>"))
})

assert("format(fragment = FALSE) wraps in DOCTYPE", {
  html = format(x, fragment = FALSE)
  (has_match(html, "<!DOCTYPE html>.*</html>"))
})

assert("format(assets = FALSE) omits runtime", {
  html = unclass(format(x, assets = FALSE))
  (has_match(html, "<style>", negate = TRUE))
  (has_match(html, "LT\\.build", negate = TRUE))
  (has_match(html, "<script>"))
})

assert("format() ships the graphics module (before core) only for plot tables", {
  op = options(lt.assets_url = "x/"); on.exit(options(op))
  eb = lt(data.frame(est = 1, lo = 0, hi = 2)) |> lt_errorbar(est ~ lo + hi)
  html = format(eb, inline_assets = FALSE)
  (grepl('x/lt-plot.js', html, fixed = TRUE))
  (grepl('x/lt-plot.css', html, fixed = TRUE))
  # plot module must precede core runtime: core reads LT.cells when it
  # drains queue, so later-registered renderer would miss this table
  (isTRUE(regexpr('x/lt-plot.js', html, fixed = TRUE) <
            regexpr('"x/lt.js"', html, fixed = TRUE)))
  # plain table pulls in neither plot asset
  plain = format(lt(d), inline_assets = FALSE)
  (grepl('lt-plot', plain, fixed = TRUE) %==% FALSE)
})

assert("lt_sparkline() records a sparkline op and hides extra columns", {
  # single list-column: series lives in that column; nothing hidden;
  # chart type travels as `kind` (not `type`, which names the op itself)
  d = data.frame(g = c("a", "b"))
  d$s = list(c(1, 2, 3), c(4, 5, 6))
  ops = (lt(d) |> lt_sparkline(~ s))$ops
  sp = ops[[length(ops)]]
  (sp$type %==% "sparkline")
  (sp$kind %==% "line")
  (unclass(sp$columns) %==% "s")
  (any(vapply(ops, function(o) o$type == "hide", logical(1))) %==% FALSE)

  # several columns: all but first hidden by default; limits set shared
  # scale; non-default type carried through
  m = data.frame(a = 1, b = 2, c = 3)
  ops = (lt(m) |> lt_sparkline(~ a + b + c, type = "bar", limits = c(0, 10)))$ops
  sp = ops[[length(ops)]]
  (sp$kind %==% "bar")
  (unclass(sp$columns) %==% c("a", "b", "c"))
  (c(sp$min, sp$max) %==% c(0, 10))
  hid = Filter(function(o) o$type == "hide", ops)[[1]]
  (unclass(hid$columns) %==% c("b", "c"))

  # hide = FALSE keeps the extra columns
  ops = (lt(m) |> lt_sparkline(~ a + b + c, hide = FALSE))$ops
  (any(vapply(ops, function(o) o$type == "hide", logical(1))) %==% FALSE)
})

assert("inline_safe() escapes </script in content", {
  (has_match(inline_safe("x</script>y"), "<\\\\/script"))
  (has_match(inline_safe("x</SCRIPT>y"), "<\\\\/SCRIPT"))
  # other tags unchanged
  (inline_safe("x</div>y") %==% "x</div>y")
})

assert("asset_url() uses local file:// when lt.local = TRUE", {
  op = options(lt.local = TRUE)
  on.exit(options(op))
  url = asset_url("lt.js")
  (has_match(url, "file://.*lt\\.js"))
})

assert("asset_url() uses CDN by default", {
  op = options(lt.local = NULL, lt.assets_url = NULL)
  on.exit(options(op))
  url = asset_url("lt.js")
  (has_match(url, "cdn\\.jsdelivr\\.net.*lt\\.min\\.js"))
})

assert("asset_url() respects lt.assets_url option", {
  op = options(lt.assets_url = "https://example.com/")
  on.exit(options(op))
  url = asset_url("lt.js")
  (url %==% "https://example.com/lt.js")
})

assert("spec_block() emits the missing default from the lt.missing option", {
  op = options(lt.missing = NULL); on.exit(options(op), add = TRUE)
  # unset: no `missing` field shipped (runtime defaults to em dash)
  sb = paste(spec_block(lt(data.frame(a = 1))), collapse = "")
  (grepl('"missing"', sb) %==% FALSE)

  # custom option value used verbatim
  options(lt.missing = "n/a")
  sb = paste(spec_block(lt(data.frame(a = 1))), collapse = "")
  (has_match(sb, '"missing": *"n/a"'))

  # empty string shipped, overrides runtime default, keeps NAs blank
  options(lt.missing = "")
  sb = paste(spec_block(lt(data.frame(a = 1))), collapse = "")
  (has_match(sb, '"missing": *""'))
})

assert("spec_block() records explicit column order for array-index names", {
  # Array-index column names ("1", "2") get reordered ahead of string
  # names by JSON object round-trip; spec_block must emit `columns` so
  # renderer can restore original order.
  d = data.frame(rowname = "Z", "1" = 1, "2" = 2, check.names = FALSE)
  sb = paste(spec_block(lt(d)), collapse = "")
  (has_match(sb, '"columns".*\\[.*"rowname".*"1".*"2"'))

  # Ordinary names keep insertion order in JSON, so `columns` is omitted.
  sb2 = paste(spec_block(lt(data.frame(a = 1, b = 2))), collapse = "")
  (grepl('"columns"', sb2) %==% FALSE)

  # Non-array-index numeric-looking names are plain string keys; also omitted.
  d3 = data.frame(x = 1, y = 2, check.names = FALSE)
  names(d3) = c("-1", "1.5")
  sb3 = paste(spec_block(lt(d3)), collapse = "")
  (grepl('"columns"', sb3) %==% FALSE)
})

assert("lt_spec() returns a render-ready spec and drops css/rules", {
  x2 = lt(d) |> lt_align("x", "center") |> lt_interactive()
  x2$css = "some.css"; x2$rules = ".na { color: red }"
  s = lt_spec(x2)
  (is.list(s))
  (all(c("data", "ops", "interactive") %in% names(s)))
  (is.null(s$css))
  (is.null(s$rules))
})

assert("lt_spec() is the payload spec_block() serializes", {
  x2 = lt(d) |> lt_interactive()
  j = xfun::tojson(lt_spec(x2))
  sb = paste(spec_block(x2), collapse = "")
  (grepl(j, sb, fixed = TRUE))
})

if (requireNamespace("knitr", quietly = TRUE)) {
  assert("knit_once() fires only on the first use of a flag per document", {
    f = "lt.test_once"
    knitr::opts_knit$set(set_names(list(NULL), f))  # reset to unseen
    on.exit(knitr::opts_knit$set(set_names(list(NULL), f)))
    (knit_once(f) %==% TRUE)   # first table emits bundle
    (knit_once(f) %==% FALSE)  # later tables skip it
    (knit_once(f) %==% FALSE)
  })

  assert("wrap_assets() brackets html with before/after tags", {
    (wrap_assets("T", "B", "A") %==% "B\nT\nA")
    (wrap_assets("T", c("B1", "B2")) %==% "B1\nB2\nT")  # before-only
    (wrap_assets("T") %==% "T")
  })
}

if (requireNamespace("htmltools", quietly = TRUE)) {
  assert("lt_dependency(plot = TRUE) loads the plot script before core", {
    dp = lt_dependency(plot = TRUE)
    # plot script loads before core so renderer registers in time
    (isTRUE(match("lt-plot.js", dp$script) < match("lt.js", dp$script)))
  })
}

assert("tidy_html() indents block tags and keeps rows on one line", {
  html = c(
    '<div class="lt-wrap"><table class="lt-table"><thead>',
    '<tr><th>a</th><th>b</th></tr></thead>',
    '<tbody><tr><td>1</td><td>2</td></tr></tbody></table></div>'
  )
  lines = tidy_html(html)
  # one line per structural tag, indented by depth
  (lines[1] %==% '<div class="lt-wrap">')
  (lines[2] %==% '  <table class="lt-table">')
  (lines[3] %==% '    <thead>')
  (lines[4] %==% '      <tr>')
  # each cell on single line, content inline
  (lines[5] %==% '        <th>a</th>')
  (lines[6] %==% '        <th>b</th>')
  (lines[7] %==% '      </tr>')
  (lines[8] %==% '    </thead>')
  # closing tags dedent to opening level
  (lines[length(lines) - 1] %==% '  </table>')
  (lines[length(lines)] %==% '</div>')
})

# which tables in a fuse()d document define (`def`) or reference (`ref`) keyed
# data, or embed it (`inline`)
share_show = function(dir, f) {
  out = litedown::fuse(file.path(dir, f), 'markdown', envir = environment(), quiet = TRUE)
  x = unlist(strsplit(out, '\n'))
  x = x[grepl('LT.d||', x, fixed = TRUE) | grepl('^ *"data(_key)?": ', x)]
  ifelse(grepl('LT.d||', x, fixed = TRUE), 'def', ifelse(grepl('"data_key"', x), 'ref', 'inline'))
}

# needs litedown's document-level store (.env$doc)
if (xfun::pkg_available('litedown', '0.11.9'))
assert("fuse() encodes repeated data once, across child documents but not separate fuse() calls", {
  dir = tempfile(); dir.create(dir)
  # chunk types: table, child document, or fuse() whose output isn't included
  rmd = function(...) unlist(lapply(c(...), function(z) switch(z,
    lt = c('```{r}', 'lt::lt(data.frame(x = 1:200, y = 200:1))', '```'),
    fuse = c('```{r}', 'invisible(litedown::fuse(file.path(dir, "inner.Rmd"), "markdown", envir = environment(), quiet = TRUE))', '```'),
    c(sprintf('```{r, child="%s.Rmd"}', z), '```')
  )))
  w = function(f, ...) writeLines(rmd(...), file.path(dir, f))
  w('child.Rmd', 'lt'); w('inner.Rmd', 'lt')
  w('a.Rmd', 'lt', 'child', 'lt')  # parent first, then child, then parent
  (share_show(dir, 'a.Rmd') %==% c('def', 'ref', 'ref', 'ref'))
  w('b.Rmd', 'child', 'lt')  # child first: parent reuses its data
  (share_show(dir, 'b.Rmd') %==% c('def', 'ref', 'ref'))
  # a fuse() inside a chunk doesn't share with its caller
  w('c.Rmd', 'fuse', 'lt')
  (share_show(dir, 'c.Rmd') %==% c('def', 'ref'))
  # nothing leaks from one top-level fuse() call to the next
  (share_show(dir, 'a.Rmd') %==% c('def', 'ref', 'ref', 'ref'))

  # data below `lt.share_size` stays inline; Inf disables sharing
  op = options(lt.share_size = 1e6); on.exit(options(op))
  (share_show(dir, 'a.Rmd') %==% rep('inline', 3))
})
