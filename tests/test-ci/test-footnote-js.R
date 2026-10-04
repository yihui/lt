# Footnotes: tfoot rendering and markers on title, column labels, and row
# groups (starts_with and rowspan modes).

assert("footnotes render in tfoot", {
  html = build(list(
    data = list(x = 1),
    footnotes = list(list(
      text = "A note",
      location = list(type = "column_labels", columns = list("x"))
    ))
  ))
  (matches(html, '.*<tfoot class="lt-footer">.*> A note</td>.*') %==% "")
})

assert("footnote on the title renders a marker in the caption", {
  html = build(list(
    data = list(x = 1),
    header = list(title = "T"),
    footnotes = list(list(
      text = "tn", location = list(type = "title", group = "title")
    ))
  ))
  (matches(html, '.*class="lt-title".*class="lt-fnref".*> tn</td>.*') %==% "")
})

assert("footnote on row groups matches by starts_with", {
  html = build(list(
    data = list(g = c("Apple", "Banana"), v = c(1, 2)),
    row_group = "g",
    footnotes = list(list(
      text = "sn",
      location = list(type = "row_groups", match = "starts_with", value = "App")
    ))
  ))
  # Marker attaches to the "Apple" group header, and only one footnote exists.
  (matches(html, '.*Apple<sup class="lt-fnref".*> sn</td>.*') %==% "")
  (matches(html, ".*Banana<sup.*") %==% html)
})

assert("footnote on row groups renders in rowspan mode", {
  # An array row_group uses rowspan mode; the footnote marker must still
  # attach to the group label cell (previously only separator-row mode did).
  html = build(list(
    data = list(g = c("A", "A", "B"), v = c(1, 2, 3)),
    row_group = list("g"),
    footnotes = list(list(
      text = "fn",
      location = list(type = "row_groups", match = "exact", values = list("A"))
    ))
  ))
  # Marker on the "A" label cell; "B" has no marker; one footnote in tfoot.
  (matches(html, '.*class="lt-row-group lt-row-open">A<sup class="lt-fnref".*') %==% "")
  (matches(html, ".*>B<sup.*") %==% html)
})
