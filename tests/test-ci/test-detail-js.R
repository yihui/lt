# Interactive row detail (browser): expanding rows, inline js() callbacks,
# column-name details, and interactive detail tables.

assert("expanding a row reveals its detail, which follows the row", {
  # an inline js() callback builds a one-cell detail table from the row's values
  x = itbl(detail = js('(row) => ({ data: { d: [row.name + ":" + row.n] } })'))
  caret = function(i) sprintf('t.querySelectorAll("tbody .lti-expand")[%d].click()', i)
  # one caret per body row, nothing expanded yet
  (lti_eval(x, 't.querySelectorAll("tbody .lti-expand").length') %==% '4')
  (lti_eval(x, 't.querySelectorAll(".lti-detail:not([hidden])").length') %==% '0')
  # expanding the first row inserts a detail row carrying the built table
  open0 = caret(0)
  (lti_eval(x, 't.querySelectorAll(".lti-detail:not([hidden])").length', open0) %==% '1')
  (lti_eval(x, 't.querySelector(".lti-detail:not([hidden]) .lt-table td").textContent', open0) %==% 'Rash:5')
  (lti_eval(x, 't.querySelector(".lti-detail:not([hidden]) td").colSpan', open0) %==% '2')
  (lti_eval(x, 't.querySelectorAll(".lti-expand")[0].ariaExpanded', open0) %==% 'true')
  # collapsing it again hides the detail row (it stays built in the DOM)
  (lti_eval(x, 't.querySelectorAll(".lti-detail:not([hidden])").length',
            paste(open0, caret(0), sep = ';')) %==% '0')
  # it stays open across a sort (which re-renders <tbody>) and follows its row:
  # after sorting by n ascending, Rash (n = 5) moves, and its detail trails it
  srt = paste(open0,
    'document.querySelectorAll("thead th .lti-label")[1].click()',
    sep = ';')
  (lti_eval(x, 't.querySelectorAll(".lti-detail:not([hidden])").length', srt) %==% '1')
  (lti_eval(
    x,
    't.querySelector(".lti-detail:not([hidden])").previousElementSibling.cells[0].textContent.includes("Rash")',
    srt
  ) %==% 'true')
})

assert("expanding or collapsing a row on the same page does not rebuild <tbody>", {
  x = itbl(detail = js('(row) => ({ data: { d: [row.name] } })'))
  caret = function(i) sprintf('t.querySelectorAll("tbody .lti-expand")[%d].click()', i)
  # pin a sibling row, then expand/collapse the first; a full <tbody> rebuild
  # would detach it, so staying connected proves only one row was touched
  js = paste('window.PIN = t.querySelectorAll("tbody tr")[1]',
             caret(0), caret(0), sep = ';')
  (lti_eval(x, 'window.PIN.isConnected', js) %==% 'true')
  # expanding alone keeps the sibling connected and shows exactly one detail row
  js1 = paste('window.PIN = t.querySelectorAll("tbody tr")[1]', caret(0), sep = ';')
  (lti_eval(x, 'window.PIN.isConnected + "," + t.querySelectorAll(".lti-detail:not([hidden])").length', js1)
   %==% 'true,1')
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
  (lti_eval(x, 't.querySelector(".lti-detail:not([hidden]) .lt-table td").textContent', open0)
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
  (lti_eval(x, '[...t.querySelectorAll(".lti-detail:not([hidden]) .lt-table th")].map(c => c.textContent).join("|")', open0)
   %==% 'n|secret')
  (lti_eval(x, '[...t.querySelectorAll(".lti-detail:not([hidden]) .lt-table tbody td")].map(c => c.textContent).join("|")', open0)
   %==% '5.0|p')
})

assert("el._lt.resetDetail rebuilds an open detail from its callback", {
  # callback output depends on a page flag (e.g. forestly's "hide placebo"
  # funnel); detail is memoized per row at first expand, so callers must bust it
  x = itbl(detail = js('(row) => ({ data: { d: [window.HIDE ? "H" : row.name] } })'))
  cell = 't.querySelector(".lti-detail:not([hidden]) .lt-table td").textContent'
  caret = 't.querySelectorAll("tbody .lti-expand")[0].click()'
  (lti_eval(x, cell, caret) %==% 'Rash')
  # closing, flipping the flag, and reopening alone shows the stale cached value
  stale = paste(caret, caret, 'window.HIDE = true', caret, sep = ';')
  (lti_eval(x, cell, stale) %==% 'Rash')
  # resetDetail() drops the cache and re-renders the open detail from the callback
  reset = paste(caret, 'window.HIDE = true', 't._lt.resetDetail()', sep = ';')
  (lti_eval(x, cell, reset) %==% 'H')
  # a single-row argument busts only that row's detail
  reset1 = paste(caret, 'window.HIDE = true', 't._lt.resetDetail(1)', sep = ';')
  (lti_eval(x, cell, reset1) %==% 'H')
})

assert("a detail table is itself interactive when its spec opts in", {
  # the callback returns a spec with its own `interactive` field: the mounted
  # detail table enhances like any other (here its headers become sortable)
  x = itbl(detail = js(
    '(row) => ({ data: { k: ["x", "y"], v: [2, 1] }, interactive: { sort: true } })'))
  open0 = 't.querySelectorAll("tbody .lti-expand")[0].click()'
  (lti_eval(x, 't.querySelectorAll(".lti-detail:not([hidden]) .lt-table .lti-sortable").length', open0)
   %==% '2')
})

assert("the table pre-sizes to its first row detail so expanding does not jump", {
  # detail far wider than the table: at idle lt opens the first row's detail,
  # measures it, and sets the table `width`, so later expands change nothing.
  # Async, so drive the browser directly and poll.
  x = itbl(detail = js('(row) => ({ data: Object.fromEntries(
    Array.from({length: 30}, (_, i) => ["c" + i, ["cell_" + i + "_" + row.name]])) })'))
  f = tempfile(fileext = '.html'); on.exit(unlink(f), add = TRUE)
  xfun::write_utf8(format(x, fragment = FALSE), f)
  b = lti_session()
  b$Page$navigate(paste0('file://', normalizePath(f)), wait_ = FALSE)
  ev = function(e) tryCatch(b$Runtime$evaluate(e)$result$value, error = function(.) NULL)
  # poll until pre-size has set an explicit width (sized via `width`, not min-width)
  w = ''
  for (i in 1:2000) { w = ev('(document.querySelector(".lt-table")||{style:{}}).style.width || ""')
    if (nzchar(w)) break; Sys.sleep(0.005) }
  (nzchar(w) %==% TRUE)
  (ev('(document.querySelector(".lt-table").style.minWidth || "") === ""') %==% TRUE)
  # expanding the first row does not change the (already pre-sized) table width
  before = ev('Math.round(document.querySelector(".lt-table").getBoundingClientRect().width)')
  ev('t = document.querySelector(".lt-table"); t.querySelectorAll("tbody .lti-expand")[0].click()')
  after = ev('Math.round(document.querySelector(".lt-table").getBoundingClientRect().width)')
  (abs(before - after) <= 1)
})

assert("a later, wider detail grows the table width when first opened", {
  # presize measures only the first row's detail (narrow here); a later, far
  # wider detail grows the table when first opened, then never jumps
  x = itbl(detail = js('(row) => ({ data: Object.fromEntries(
    Array.from({length: row.name === "Rash" ? 1 : 40}, (_, i) =>
      ["c" + i, ["cell_" + i + "_" + row.name]])) })'))
  f = tempfile(fileext = '.html'); on.exit(unlink(f), add = TRUE)
  xfun::write_utf8(format(x, fragment = FALSE), f)
  b = lti_session()
  b$Page$navigate(paste0('file://', normalizePath(f)), wait_ = FALSE)
  ev = function(e) tryCatch(b$Runtime$evaluate(e)$result$value, error = function(.) NULL)
  width = 'Math.round(document.querySelector(".lt-table").getBoundingClientRect().width)'
  # wait until presize has run (it builds the first row's detail, kept hidden)
  for (i in 1:2000) { if (isTRUE(ev('!!document.querySelector(".lti-detail")'))) break
    Sys.sleep(0.005) }
  base = ev(width)
  # open the second row (Nausea), whose detail is far wider -> the table grows
  ev('t = document.querySelector(".lt-table"); t.querySelectorAll("tbody .lti-expand")[1].click()')
  wide = ev(width)
  (wide > base)
  # close and reopen it: now the width is pinned, so it does not jump
  ev('t.querySelectorAll("tbody .lti-expand")[1].click()')
  ev('t.querySelectorAll("tbody .lti-expand")[1].click()')
  (abs(ev(width) - wide) <= 1)
})
