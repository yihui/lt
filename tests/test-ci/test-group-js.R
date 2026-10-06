# Row groups: separator rows, rowspan labels and fillers, column-width
# alignment past group columns, and sorting by groups.

assert("separator row groups render correctly", {
  html = build(list(
    data = list(g = c("A", "A", "B"), v = 1:3),
    row_group = "g"
  ))
  (matches(html, '.*class="lt-row-group".*>A</th>.*>B</th>.*') %==% "")
})

assert("rowspan row groups render label + filler cells", {
  # A group of n > 1 rows puts its label in a non-spanning cell (so it aligns
  # with the row's body cells) plus an empty filler spanning the rest. Group
  # "A" spans 3 rows: label on row 1, filler with rowspan="2" after. The
  # single-row group "B" is just a plain label cell (no filler, no rowspan).
  html = build(list(
    data = list(g = c("A", "A", "A", "B"), v = 1:4),
    row_group = list("g")
  ))
  (matches(html, '.*<th scope="row" class="lt-row-group lt-row-open">A</th>.*') %==% "")
  (matches(html, '.*<th class="lt-row-group" rowspan="2"></th>.*') %==% "")
  (matches(html, '.*<th scope="row" class="lt-row-group">B</th>.*') %==% "")
  # the label cell must not span rows itself
  (grepl('rowspan="[0-9]+">A</th>', html) %==% FALSE)
})

assert("two-row group filler omits the rowspan attribute", {
  # A 2-row group leaves n-1 = 1 filler row, which needs no rowspan attribute.
  html = build(list(
    data = list(g = c("A", "A"), v = 1:2),
    row_group = list("g")
  ))
  (matches(html, '.*<th class="lt-row-group"></th>.*') %==% "")
  (grepl('rowspan', html) %==% FALSE)
})

assert("column widths align past rowspan group columns", {
  # A width set on a body column must apply to that column, not shift onto the
  # leading rowspan group column. The colgroup gets an empty <col> per group
  # column, so the width lands on the correct <col>.
  html = build(list(
    data = list(g = c("A", "A"), v = 1:2),
    row_group = list("g"),
    ops = list(list(type = "width", widths = list(v = "9em")))
  ))
  (matches(html, '.*<colgroup><col><col style="width:9em"></colgroup>.*') %==% "")
})

assert("full-width control rows span the rowspan group columns too", {
  # a rowspan group adds a leading column that is not in `_cols`; the table-wide
  # control rows (head bar, pager, no-match row, detail) must span it as well, or
  # they fall short of the table's full width
  d = data.frame(g = c("A", "A", "B"), x = c(1, 2, 3), y = c(4, 5, 6))
  x = lt(d) |> lt_group(~ g) |>
    lt_interactive(pager = 2, search = TRUE, download = TRUE)
  # 3 = 1 group column + 2 data columns
  (lti_eval(x, 't.querySelector(".lti-head td").colSpan') %==% '3')
  (lti_eval(x, 't.querySelector(".lti-pager-row td").colSpan') %==% '3')
  miss = 'var s = t.querySelector(".lti-bar input[type=search]");
          s.value = "zzz"; s.dispatchEvent(new Event("change"))'
  (lti_eval(x, 't.querySelector(".lti-empty td").colSpan', miss) %==% '3')
  xd = lt(d) |> lt_group(~ g) |> lt_interactive(detail = ~ y)
  open = 't.querySelector(".lti-expand").click()'
  (lti_eval(xd, 't.querySelector(".lti-detail td").colSpan', open) %==% '3')
})

assert("an under-header filter lines up past the rowspan group columns", {
  # the filter row leads with the group columns' (empty) cells, so each column's
  # funnel sits under its own header rather than shifting left by the group count
  d = data.frame(g = c("A", "A", "B"), x = c(1, 2, 3), y = c(4, 5, 6))
  x = lt(d) |> lt_group(~ g) |> lt_interactive(filter = list(y = "range"))
  # 3 = 1 group cell + x + y; the funnel's cell is the last one (column y)
  (lti_eval(x, 't.querySelectorAll(".lti-filters > td").length') %==% '3')
  (lti_eval(x, 't.querySelector(".lti-filters .lti-funnel").closest("td").cellIndex')
   %==% lti_eval(x, '[...t.querySelectorAll("thead th")].find(th => th.textContent.trim() === "y").cellIndex'))
})

assert("sort by groups reorders rows", {
  html = build(list(
    data = list(g = c("B", "A", "B", "A"), v = c(1, 2, 3, 4)),
    row_group = list("g")
  ))
  # After sorting by g, A rows (2,4) come before B rows (1,3)
  (matches(html, ".*>2</td>.*>1</td>.*") %==% "")
})
