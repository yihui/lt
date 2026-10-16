# Cell styling: conditional classes, merging with alignment classes, and the
# _viewRows seam that reorders/subsets the rendered rows.

assert("style with class and test", {
  html = build(list(
    data = list(x = c(1, 5)),
    ops = list(list(type = "style", columns = list("x"), test = "v => v > 3", class = "hi"))
  ))
  # "hi" applied to cell with 5 but not cell with 1
  (has_match(html, 'hi">5</td>'))
  (has_match(html, !'hi">1</td>'))
})

assert("_viewRows sets tbody row order and subset", {
  # The interactive plugin's core seam: <tbody> iterates the given 1-based
  # original row indices (order + subset) instead of all rows.
  html = build(list(data = list(x = c(10, 20, 30)), `_viewRows` = c(3L, 1L)))
  (has_match(html, ">30</td>.*>10</td>"))
  (has_match(html, !">20<"))
  # row-indexed styles stay keyed to the original index after reordering
  html = build(list(
    data = list(x = c(10, 20, 30)), `_viewRows` = c(3L, 1L),
    ops = list(list(type = "style", columns = list("x"), rows = list(3L), class = "hot"))
  ))
  (has_match(html, 'class="al-r hot">30</td>.*>10</td>'))
})

assert("per-cell style class merges with the column alignment class", {
  # Numeric columns get the "al-r" class; a style class on one cell must be
  # appended, not replace it.
  html = build(list(
    data = list(x = c(1, 5)),
    ops = list(list(type = "style", columns = list("x"), rows = list(2L), class = "hot"))
  ))
  (has_match(html, 'class="al-r hot">5</td>'))
  # The untouched cell keeps just the alignment class.
  (has_match(html, 'class="al-r">1</td>'))
})
