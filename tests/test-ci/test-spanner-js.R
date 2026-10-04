# Column spanners: colspan rendering and reordering columns to body order.

assert("column spanner renders colspan", {
  html = build(list(
    data = list(a = 1, b = 2, c = 3),
    spanners = list(list(label = "AB", columns = list("a", "b")))
  ))
  (matches(html, '.*colspan="2".*>AB</th>.*') %==% "")
})

assert("spanner columns are reordered to body order before rendering", {
  # columns listed out of order (b before a) still render as one spanner
  html = build(list(
    data = list(a = 1, b = 2, c = 3),
    spanners = list(list(label = "AB", columns = list("b", "a")))
  ))
  (matches(html, '.*colspan="2".*>AB</th>.*') %==% "")

  # after a move, a spanner whose columns are listed in the original (pre-move)
  # order must anchor to the moved first column, not be dropped
  html = build(list(
    data = list(x = 1, a = 2, b = 3),
    ops = list(list(type = "move", columns = list("b", "a"), after = "x")),
    # body order becomes x, b, a; list spanner cols in the pre-move order
    spanners = list(list(label = "AB", columns = list("a", "b")))
  ))
  (matches(html, '.*colspan="2".*>AB</th>.*') %==% "")
})
