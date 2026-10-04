# External filter controller: el._lt.filter() for outside widgets (browser).

assert("el._lt.filter lets outside widgets filter the table, composing with AND", {
  # forestly builds its own dropdown/range widgets and drives the table through
  # this controller rather than the built-in boxes
  x = itbl(pager = FALSE)
  rows = 't.querySelectorAll("tbody tr").length'
  (lti_eval(x, rows) %==% '4')
  # a predicate over the row's raw values (keyed by column) keeps matching rows
  big = 't._lt.filter("big", row => row.n > 5)'
  (lti_eval(x, rows, big) %==% '2')
  # a second predicate under another id composes with AND
  both = paste(big, 't._lt.filter("nm", row => row.name !== "Nausea")', sep = ';')
  (lti_eval(x, rows, both) %==% '1')
  # a null fn removes just that one predicate
  (lti_eval(x, rows, paste(both, 't._lt.filter("big", null)', sep = ';')) %==% '3')
  # a predicate survives a re-render (here, sorting a column)
  sortN = paste(big, 'document.querySelector("thead th").click()', sep = ';')
  (lti_eval(x, rows, sortN) %==% '2')
})

assert("external predicates see hidden columns too (not just the visible ones)", {
  # forestly's slider/dropdown filter on helper columns that are hidden from the
  # table; the row object handed to a predicate must still carry them
  x = lt(data.frame(name = sym, n = c(5, 12, 3, 8), g = c("a", "b", "a", "b"))) |>
    lt_hide("g") |> lt_interactive(pager = FALSE)
  rows = 't.querySelectorAll("tbody tr").length'
  (lti_eval(x, rows, 't._lt.filter("g", row => row.g === "a")') %==% '2')
})
