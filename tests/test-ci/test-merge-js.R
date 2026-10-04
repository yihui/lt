# Column merge: pattern substitution and conditional "<<...>>" blocks.

assert("merge with pattern", {
  html = build(list(
    data = list(a = "x", b = "y"),
    ops = list(list(type = "merge", columns = list("a", "b"), pattern = "{1} ({2})", hide = TRUE))
  ))
  (matches(html, '.*>x \\(y\\)</td>.*') %==% "")
})

assert("merge drops a conditional block when its references are empty", {
  # "<<...>>" blocks are emitted only if all {n} refs are non-empty.
  html = build(list(
    data = list(a = "x", b = "", c = ""),
    ops = list(list(type = "merge", columns = list("a", "b", "c"),
                    pattern = "{1}<<({2}/{3})>>"))
  ))
  (matches(html, ".*>x</td>.*") %==% "")
  (matches(html, ".*\\(/\\).*") %==% html)
})
