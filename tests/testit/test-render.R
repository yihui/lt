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
