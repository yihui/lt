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
