d = data.frame(x = 1:2, y = c("a", "b"))
x = lt(d)

assert("format() returns HTML with script tags", {
  html = format(x)
  (is.character(html))
  (any(grepl("<script>", html)))
  (any(grepl("</script>", html)))
})

assert("format(fragment = FALSE) wraps in DOCTYPE", {
  html = format(x, fragment = FALSE)
  (any(grepl("<!DOCTYPE html>", html)))
  (any(grepl("</html>", html)))
})

assert("format(assets = FALSE) omits runtime", {
  html = format(x, assets = FALSE)
  (!any(grepl("<style>", html)))
  (!any(grepl("LT.build", html)))
  (any(grepl("<script>", html)))
})

assert("inline_safe() escapes </script in content", {
  (grepl("<\\\\/script", inline_safe("x</script>y")))
  (grepl("<\\\\/SCRIPT", inline_safe("x</SCRIPT>y")))
  # does not alter other tags
  (inline_safe("x</div>y") %==% "x</div>y")
})

assert("asset_url() uses local file:// when lt.local = TRUE", {
  op = options(lt.local = TRUE)
  on.exit(options(op))
  url = asset_url("lt.js")
  (grepl("^file://", url))
  (grepl("lt\\.js$", url))
})

assert("asset_url() uses CDN by default", {
  op = options(lt.local = NULL, lt.assets_url = NULL)
  on.exit(options(op))
  url = asset_url("lt.js")
  (grepl("cdn.jsdelivr.net", url))
  (grepl("lt\\.min\\.js$", url))
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
  (!grepl("some\\.css", html))
  (!grepl("color: red", html))
  (grepl("LT", html))
})
