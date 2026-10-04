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
