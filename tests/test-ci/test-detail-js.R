# Interactive row detail (browser): expanding rows, inline js() callbacks,
# column-name details, and interactive detail tables.

assert("expanding a row reveals its detail, which follows the row", {
  # an inline js() callback builds a one-cell detail table from the row's values
  x = itbl(detail = js('(row) => ({ data: { d: [row.name + ":" + row.n] } })'))
  caret = function(i) sprintf('t.querySelectorAll("tbody .lti-expand")[%d].click()', i)
  # one caret per body row, nothing expanded yet
  (lti_eval(x, 't.querySelectorAll("tbody .lti-expand").length') %==% '4')
  (lti_eval(x, 't.querySelectorAll(".lti-detail").length') %==% '0')
  # expanding the first row inserts a detail row carrying the built table
  open0 = caret(0)
  (lti_eval(x, 't.querySelectorAll(".lti-detail").length', open0) %==% '1')
  (lti_eval(x, 't.querySelector(".lti-detail .lt-table td").textContent', open0) %==% 'Rash:5')
  (lti_eval(x, 't.querySelector(".lti-detail td").colSpan', open0) %==% '2')
  (lti_eval(x, 't.querySelectorAll(".lti-expand")[0].ariaExpanded', open0) %==% 'true')
  # collapsing it again removes the detail row
  (lti_eval(x, 't.querySelectorAll(".lti-detail").length',
            paste(open0, caret(0), sep = ';')) %==% '0')
  # it stays open across a sort (which re-renders <tbody>) and follows its row:
  # after sorting by n ascending, Rash (n = 5) moves, and its detail trails it
  srt = paste(open0,
    'document.querySelectorAll("thead th .lti-label")[1].click()',
    sep = ';')
  (lti_eval(x, 't.querySelectorAll(".lti-detail").length', srt) %==% '1')
  (lti_eval(
    x,
    't.querySelector(".lti-detail").previousElementSibling.cells[0].textContent.includes("Rash")',
    srt
  ) %==% 'true')
})

assert("row detail takes an inline js() callback and sees hidden columns", {
  # `secret` is hidden from the main table but still reaches the callback,
  # which travels verbatim in the spec (no function need be defined on the page)
  x = lt(data.frame(name = sym, n = c(5, 12, 3, 8),
                    secret = c("p", "q", "r", "s"))) |>
    lt_hide("secret") |>
    lt_interactive(detail = js('(row) => ({ data: { d: [row.secret] } })'))
  # the hidden column is absent from the main table's headers
  (lti_eval(x, '[...t.querySelectorAll("thead th")].some(h => h.textContent === "secret")')
   %==% 'false')
  # expanding the first row builds its detail straight from the callback,
  # surfacing the hidden value
  open0 = 't.querySelectorAll("tbody .lti-expand")[0].click()'
  (lti_eval(x, 't.querySelector(".lti-detail .lt-table td").textContent', open0)
   %==% 'p')
})

assert("detail = column names builds a one-row table of displayed values", {
  # name the columns to show; `secret` is hidden from the main table but still
  # reachable in the detail, and `n` is formatted, so the detail shows that
  # formatted text (5.0), not the raw value (5).
  x = lt(data.frame(name = sym, n = c(5, 12, 3, 8),
                    secret = c("p", "q", "r", "s"))) |>
    lt_format(~ n, decimals = 1) |>
    lt_hide("secret") |>
    lt_interactive(detail = ~ n + secret)
  open0 = 't.querySelectorAll("tbody .lti-expand")[0].click()'
  # the named columns become headers, their displayed values a single row
  (lti_eval(x, '[...t.querySelectorAll(".lti-detail .lt-table th")].map(c => c.textContent).join("|")', open0)
   %==% 'n|secret')
  (lti_eval(x, '[...t.querySelectorAll(".lti-detail .lt-table tbody td")].map(c => c.textContent).join("|")', open0)
   %==% '5.0|p')
})

assert("a detail table is itself interactive when its spec opts in", {
  # the callback returns a spec with its own `interactive` field: the mounted
  # detail table enhances like any other (here its headers become sortable)
  x = itbl(detail = js(
    '(row) => ({ data: { k: ["x", "y"], v: [2, 1] }, interactive: { sort: true } })'))
  open0 = 't.querySelectorAll("tbody .lti-expand")[0].click()'
  (lti_eval(x, 't.querySelectorAll(".lti-detail .lt-table .lti-sortable").length', open0)
   %==% '2')
})
