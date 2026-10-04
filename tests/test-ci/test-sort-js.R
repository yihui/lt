# Interactive sorting in the browser: header clicks, shift-click multi-key,
# initial sort, and when a table is kept static (row groups, indentation).

assert("clicking a header sorts the rendered rows", {
  x = itbl()
  (lti_rows(x) %==% sym)  # no sort applied yet
  click = 'document.querySelectorAll("thead th")[1].click()'
  (lti_rows(x, click) %==% c("Headache", "Rash", "Itch", "Nausea"))       # n asc
  (lti_rows(x, paste(click, click, sep = ';')) %==%
     c("Nausea", "Itch", "Rash", "Headache"))                             # n desc
  (lti_rows(x, paste(rep(click, 3), collapse = ';')) %==% sym)            # unsorted
  # the sorted column is announced to screen readers
  (lti_eval(x, 'document.querySelectorAll("thead th")[1].ariaSort', click) %==% 'ascending')
})

assert("shift-clicking adds a sort key, so columns sort together", {
  d = data.frame(g = c("a", "a", "b", "b"), v = c(2, 1, 1, 2))
  x = lt(d) |> lt_interactive(pager = FALSE)
  gc = 'document.querySelectorAll("thead th")[0].click()'
  vs = 'document.querySelectorAll("thead th")[1].dispatchEvent(
          new MouseEvent("click", {bubbles: true, shiftKey: true}))'
  # g ascending, then v ascending as a tie-breaker within each g: v reads 1,2,1,2
  (lti_col(x, 1, paste(gc, vs, sep = ';')) %==% c("1", "2", "1", "2"))
  # both headers are announced, with an ordinal marking each key's place
  (lti_eval(x, 'document.querySelectorAll("thead th")[0].ariaSort',
            paste(gc, vs, sep = ';')) %==% 'ascending')
  ind = '[...t.querySelectorAll("thead th .lti-sort")].map(s => s.textContent).join("|")'
  (lti_eval(x, ind, paste(gc, vs, sep = ';')) %==% '▲₁|▲₂')
  # a plain click (no shift) drops the extra key, back to a single-column sort
  # (and cycles that column on, here from ascending to descending)
  (lti_eval(x, ind, paste(gc, vs, gc, sep = ';')) %==% '▼|')
})

assert("an initial sort orders the rows before any click", {
  d = data.frame(g = c("b", "a", "b", "a"), v = c(1, 2, 3, 4))
  x = lt(d) |> lt_interactive(sort = c('g', '-v'), pager = FALSE)
  # g ascending, then v descending: a(v4, v2) then b(v3, v1)
  (lti_col(x, 1) %==% c("4", "2", "3", "1"))
  (lti_eval(x, 'document.querySelectorAll("thead th")[0].ariaSort') %==% 'ascending')
  (lti_eval(x, 'document.querySelectorAll("thead th")[1].ariaSort') %==% 'descending')
})

assert("a table whose row order carries meaning is left static", {
  d = data.frame(g = c("a", "a", "b"), v = 1:3)
  # row groups
  x = lt(d) |> lt_group(~ g) |> lt_interactive()
  (lti_eval(x, '[...t.querySelectorAll(".lti-sortable")].length') %==% '0')
  # indentation (a hierarchy sorting would scramble)
  x = lt(d) |> lt_indent(2) |> lt_interactive()
  (lti_eval(x, '[...t.querySelectorAll(".lti-sortable")].length') %==% '0')
})

assert("column spanners stay interactive: they are header rows, not body rows", {
  d = data.frame(a.x = c(3L, 1L, 2L), a.y = c("p", "r", "q"), b = 1:3)
  # `a.x` and `a.y` are spanned under `a`, inferred from the column names
  x = lt(d) |> lt_spanner() |> lt_interactive()
  spans = 'sel => [...t.querySelectorAll(sel)].map(e => e.textContent).join(",")'
  # sorting is wired to the column labels, not the spanner labels above them
  (lti_eval(x, sprintf('(%s)("thead .lti-sortable")', spans)) %==% 'x,y,b')
  click = 'document.querySelectorAll("thead tr:nth-child(3) th")[0].click()'
  (lti_rows(x, click) %==% c('1', '2', '3'))
  # the spanner row survives the re-render of <tbody>
  (lti_eval(x, sprintf('(%s)(".lt-spanner")', spans), click) %==% 'a')
  # an explicit spanner works the same way
  y = lt(data.frame(p = c(2L, 1L), q = c("b", "a"))) |> lt_spanner(both ~ p + q) |>
    lt_interactive()
  (lti_eval(y, sprintf('(%s)(".lt-spanner")', spans)) %==% 'both')
  (lti_rows(y, 'document.querySelectorAll("thead tr:nth-child(3) th")[0].click()') %==%
     c('1', '2'))
})
