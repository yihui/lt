d = data.frame(x = 1:2, y = c("a", "b"))
x = lt(d)

assert("format() returns HTML with script tags", {
  html = format(x)
  (is.character(html))
  (matches(html, ".*<script>.*</script>.*") %==% "")
})

assert("format(fragment = FALSE) wraps in DOCTYPE", {
  html = format(x, fragment = FALSE)
  (matches(html, ".*<!DOCTYPE html>.*</html>.*") %==% "")
})

assert("format(assets = FALSE) omits runtime", {
  html = unclass(format(x, assets = FALSE))
  (matches(html, ".*<style>.*") %==% html)
  (matches(html, ".*LT\\.build.*") %==% html)
  (matches(html, ".*<script>.*") %==% "")
})

assert("format() ships the graphics module (before core) only for plot tables", {
  op = options(lt.assets_url = "x/"); on.exit(options(op))
  eb = lt(data.frame(est = 1, lo = 0, hi = 2)) |> lt_errorbar(est ~ lo + hi)
  html = format(eb, inline_assets = FALSE)
  (grepl('x/lt-plot.js', html, fixed = TRUE))
  (grepl('x/lt-plot.css', html, fixed = TRUE))
  # the plot module must precede the core runtime: core reads LT.cells when it
  # drains the queue, so a renderer registered later would miss this table
  (isTRUE(regexpr('x/lt-plot.js', html, fixed = TRUE) <
            regexpr('"x/lt.js"', html, fixed = TRUE)))
  # a plain table pulls in neither plot asset
  plain = format(lt(d), inline_assets = FALSE)
  (grepl('lt-plot', plain, fixed = TRUE) %==% FALSE)
})

assert("inline_safe() escapes </script in content", {
  (matches(inline_safe("x</script>y"), ".*<\\\\/script.*") %==% "")
  (matches(inline_safe("x</SCRIPT>y"), ".*<\\\\/SCRIPT.*") %==% "")
  # does not alter other tags
  (inline_safe("x</div>y") %==% "x</div>y")
})

assert("asset_url() uses local file:// when lt.local = TRUE", {
  op = options(lt.local = TRUE)
  on.exit(options(op))
  url = asset_url("lt.js")
  (matches(url, ".*file://.*lt\\.js.*") %==% "")
})

assert("asset_url() uses CDN by default", {
  op = options(lt.local = NULL, lt.assets_url = NULL)
  on.exit(options(op))
  url = asset_url("lt.js")
  (matches(url, ".*cdn\\.jsdelivr\\.net.*lt\\.min\\.js.*") %==% "")
})

assert("asset_url() respects lt.assets_url option", {
  op = options(lt.assets_url = "https://example.com/")
  on.exit(options(op))
  url = asset_url("lt.js")
  (url %==% "https://example.com/lt.js")
})

assert("spec_block() drops css and rules", {
  x2 = x
  x2$css = "some.css"
  x2$rules = ".na { color: red }"
  sb = spec_block(x2)
  html = paste(sb, collapse = "")
  (matches(html, ".*some\\.css.*") %==% html)
  (matches(html, ".*color: red.*") %==% html)
  (matches(html, ".*window\\.LT.*") %==% "")
})

assert("spec_block() emits the missing default from the lt.missing option", {
  op = options(lt.missing = NULL); on.exit(options(op), add = TRUE)
  # unset: no `missing` field is shipped (the runtime defaults to an em dash)
  sb = paste(spec_block(lt(data.frame(a = 1))), collapse = "")
  (grepl('"missing"', sb) %==% FALSE)

  # a custom option value is used verbatim
  options(lt.missing = "n/a")
  sb = paste(spec_block(lt(data.frame(a = 1))), collapse = "")
  (matches(sb, '.*"missing": *"n/a".*') %==% "")

  # empty string is shipped, to override the runtime default and keep NAs blank
  options(lt.missing = "")
  sb = paste(spec_block(lt(data.frame(a = 1))), collapse = "")
  (matches(sb, '.*"missing": *"".*') %==% "")
})

assert("spec_block() records explicit column order for array-index names", {
  # Array-index column names ("1", "2") would be reordered ahead of string
  # names by a JSON object round-trip; spec_block must emit `columns` so the
  # renderer can restore the original order.
  d = data.frame(rowname = "Z", "1" = 1, "2" = 2, check.names = FALSE)
  sb = paste(spec_block(lt(d)), collapse = "")
  (matches(sb, '.*"columns".*\\[.*"rowname".*"1".*"2".*') %==% "")

  # Ordinary names keep insertion order in JSON, so `columns` is omitted.
  sb2 = paste(spec_block(lt(data.frame(a = 1, b = 2))), collapse = "")
  (grepl('"columns"', sb2) %==% FALSE)

  # Non-array-index numeric-looking names are plain string keys — also omitted.
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
    knitr::opts_knit$set(stats::setNames(list(NULL), f))  # reset to unseen
    on.exit(knitr::opts_knit$set(stats::setNames(list(NULL), f)))
    (knit_once(f) %==% TRUE)   # first table emits the bundle
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
  assert("lt_dependency() bundles core assets; opts add extension/binding", {
    dep = lt_dependency()
    (dep$script %==% "lt.js")
    ("lt.css" %in% dep$stylesheet)
    di = lt_dependency(interactive = TRUE)
    ("lt-interactive.js" %in% di$script)
    ("lt-interactive.css" %in% di$stylesheet)
    ds = lt_dependency(shiny = TRUE)
    ("lt-binding.js" %in% ds$script)
    dp = lt_dependency(plot = TRUE)
    ("lt-plot.css" %in% dp$stylesheet)
    # the plot script loads before core so its renderer is registered in time
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
  # one line per structural tag, indented by nesting depth
  (lines[1] %==% '<div class="lt-wrap">')
  (lines[2] %==% '  <table class="lt-table">')
  (lines[3] %==% '    <thead>')
  (lines[4] %==% '      <tr>')
  # each cell stays on its own single line with its content inline
  (lines[5] %==% '        <th>a</th>')
  (lines[6] %==% '        <th>b</th>')
  (lines[7] %==% '      </tr>')
  (lines[8] %==% '    </thead>')
  # closing tags dedent back to their opening level
  (lines[length(lines) - 1] %==% '  </table>')
  (lines[length(lines)] %==% '</div>')
})
