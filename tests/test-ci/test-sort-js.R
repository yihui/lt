# Interactive sorting in the browser: header clicks, shift-click multi-key,
# initial sort, sorting within separator row groups and indented subtrees, and
# the one case still kept static (a rowspan row group).

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

assert("a rowspan row group is left static (spanning cells can't reorder)", {
  d = data.frame(g = c("a", "a", "b"), v = 1:3)
  # lt_group()'s default rendering draws the group column as rowspan cells
  x = lt(d) |> lt_group(~ g) |> lt_interactive()
  (lti_eval(x, '[...t.querySelectorAll(".lti-sortable")].length') %==% '0')
})

assert("separator row groups stay interactive, sorting within each group", {
  d = data.frame(g = c("a", "a", "b", "b"), v = c(2, 1, 4, 3))
  x = lt(d) |> lt_group(~ g, sep = TRUE) |> lt_interactive(pager = FALSE)
  # the group column is hidden; the only visible column is v
  cells = '[...t.querySelectorAll("tbody tr:not(.lt-row-group)")]
             .map(r => r.children[0].textContent).join("|")'
  heads = '[...t.querySelectorAll("tbody tr.lt-row-group th")]
             .map(e => e.textContent).join("|")'
  click = 'document.querySelector("thead th").click()'   # sort v ascending
  # v sorts within each group; the two group headers both survive, in order
  (strsplit(lti_eval(x, cells, click), '|', fixed = TRUE)[[1]] %==% c('1', '2', '3', '4'))
  (lti_eval(x, heads, click) %==% 'a|b')
  # a search that empties group b drops its header, keeping only group a
  search = 'var s = t.querySelector(".lti-search"); s.value = "x < 3";
            s.dispatchEvent(new Event("change"))'
  (lti_eval(x, heads, search) %==% 'a')
  (strsplit(lti_eval(x, cells, search), '|', fixed = TRUE)[[1]] %==% c('2', '1'))
})

assert("an indented table stays interactive, sorting siblings within a parent", {
  # A(0) with children A2,A1(1); B(0) with child B1(1)
  d = data.frame(v = c("A", "A2", "A1", "B", "B1"), n = c(3, 2, 1, 5, 4))
  x = lt(d) |> lt_indent(c(2, 3, 5)) |> lt_interactive(pager = FALSE)
  col = '[...t.querySelectorAll("tbody tr")].map(r => r.children[0].textContent).join("|")'
  (strsplit(lti_eval(x, col), '|', fixed = TRUE)[[1]] %==%
     c('A', 'A2', 'A1', 'B', 'B1'))                       # file order first
  click = 'document.querySelectorAll("thead th")[1].click()'   # sort n ascending
  # parents keep their place; each parent's children sort within it
  (strsplit(lti_eval(x, col, click), '|', fixed = TRUE)[[1]] %==%
     c('A', 'A1', 'A2', 'B', 'B1'))
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
