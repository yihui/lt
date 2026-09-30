# Exercise the interactive plugin's view pipeline (filters, search, sort, and
# paging) in Node.js. The runner loads core lt.js and lt-interactive.js into one
# context, then calls LT.plugins.interactive.computeView on a spec/display/state
# supplied as JSON, and prints the resulting 1-based row indices
# (spec._viewRows) as a CSV list. When the state asks for paging, the page
# actually shown is appended after a `|` (pageSlice clamps it into range).

RUNNER = '
const fs = require("fs"), vm = require("vm");
const ctx = {}; vm.createContext(ctx);
const run = (p, from, to) => {
  let s = fs.readFileSync(p, "utf8");
  if (from) s = s.split(from).join(to);
  vm.runInContext(s, ctx);
};
run(process.argv[2], "(window)", "(globalThis)");   // lt.js attaches ctx.LT
run(process.argv[3]);                                 // lt-interactive.js
const inp = JSON.parse(fs.readFileSync(0, "utf8"));
const spec = inp.spec, data = spec.data || {};
for (const k of Object.keys(data)) if (!Array.isArray(data[k])) data[k] = [data[k]];
spec._cols = spec._cols || Object.keys(data);
const disp = inp.disp || {};
for (const k of Object.keys(disp)) if (!Array.isArray(disp[k])) disp[k] = [disp[k]];
const int = ctx.LT.plugins.interactive, state = inp.state || {};
let view = int.computeView(spec, disp, state);
if (state.pageSize) view = int.pageSlice(view, state);
process.stdout.write(view.join(",") + (state.pageSize ? "|" + state.page : ""));
'

run_out = function(data, state = list(), disp = NULL) {
  if (is.null(disp)) disp = lapply(data, as.character)
  runner = tempfile(fileext = '.js')
  writeLines(RUNNER, runner)
  on.exit(unlink(runner), add = TRUE)
  input = xfun::tojson(list(spec = list(data = data), disp = disp, state = state))
  out = system2(
    'node',
    shQuote(c(runner, asset_path('lt.js'), asset_path('lt-interactive.js'))),
    input = input, stdout = TRUE
  )
  strsplit(paste(out, collapse = ''), '|', fixed = TRUE)[[1]]
}

as_rows = function(x) if (is.na(x) || !nzchar(x)) integer(0) else
  as.integer(strsplit(x, ',')[[1]])

# the view (the rendered row indices)
run_view = function(data, state = list(), disp = NULL)
  as_rows(run_out(data, state, disp)[1])

# the view plus the page it was taken from, for a state that asks for paging
run_page = function(data, state) {
  out = run_out(data, state)
  list(rows = as_rows(out[1]), page = as.integer(out[2]))
}

sym = c("Rash", "Nausea", "Headache", "Itch")

assert("numeric sort orders by raw value; nulls sort last both directions", {
  d = list(name = sym, n = c(5, 12, 3, 8))
  (run_view(d, list(sortCol = 'n', sortDir = 'asc')) %==% c(3L, 1L, 4L, 2L))
  (run_view(d, list(sortCol = 'n', sortDir = 'desc')) %==% c(2L, 4L, 1L, 3L))
  d2 = list(n = c(5, NA, 3))
  (run_view(d2, list(sortCol = 'n', sortDir = 'asc')) %==% c(3L, 1L, 2L))
  (run_view(d2, list(sortCol = 'n', sortDir = 'desc')) %==% c(1L, 3L, 2L))
})

assert("string columns sort locale-aware (case-insensitive letter order)", {
  d = list(g = c("banana", "Apple", "cherry"))
  (run_view(d, list(sortCol = 'g', sortDir = 'asc')) %==% c(2L, 1L, 3L))
})

assert("substring search matches display text; leading ! negates", {
  d = list(name = sym, n = c(5, 12, 3, 8))
  (run_view(d, list(term = 'rash')) %==% 1L)                # case-insensitive
  (run_view(d, list(term = '!rash')) %==% c(2L, 3L, 4L))
  (run_view(d, list(term = 'a')) %==% c(1L, 2L, 3L))        # Itch has no 'a'
  (run_view(d, list(term = '')) %==% 1:4)                   # empty ⇒ all rows
})

assert("expression mode evaluates raw values (numbers and strings)", {
  d = list(name = sym, n = c(5, 12, 3, 8))
  (run_view(d, list(term = 'x > 5')) %==% c(2L, 4L))        # n = 12, 8
  # negation (!=) keeps a row only when every searched cell satisfies it
  (run_view(d, list(term = 'x !== "Rash"')) %==% c(2L, 3L, 4L))
})

assert("substring matches display while expression matches the raw value", {
  # raw 1000, displayed with a thousands separator
  d = list(v = 1000)
  disp = list(v = "1 000")
  (run_view(d, list(term = '1 000'), disp) %==% 1L)          # matches display
  (run_view(d, list(term = '1000'), disp) %==% integer(0))   # display has a space
  (run_view(d, list(term = 'x > 500'), disp) %==% 1L)        # expression on raw
})

assert("search and sort compose (filter then sort)", {
  d = list(name = sym, n = c(5, 12, 3, 8))
  # keep rows containing 'a' (1,2,3), then sort by n descending: 12,5,3
  (run_view(d, list(term = 'a', sortCol = 'n', sortDir = 'desc')) %==% c(2L, 1L, 3L))
})

assert("a column filter looks only at its own column", {
  d = list(name = sym, n = c(5, 12, 3, 8))
  (run_view(d, list(filters = list(name = 'a'))) %==% c(1L, 2L, 3L))
  (run_view(d, list(filters = list(n = 'x > 5'))) %==% c(2L, 4L))
  # '1' is in the display of n = 12 only; the names are not searched
  (run_view(d, list(filters = list(n = '1'))) %==% 2L)
})

assert("filters and the search are combined with AND", {
  d = list(name = sym, n = c(5, 12, 3, 8))
  # 'a' in name keeps 1,2,3; n > 5 keeps 2,4
  (run_view(d, list(filters = list(name = 'a', n = 'x > 5'))) %==% 2L)
  (run_view(d, list(filters = list(name = 'a'), term = 'x > 5')) %==% 2L)
  (run_view(d, list(filters = list(name = 'a', n = 'x > 100'))) %==% integer(0))
})

assert("paging slices the view and clamps the page into range", {
  d = list(n = 1:7)
  (run_page(d, list(pageSize = 3))$rows %==% 1:3)
  (run_page(d, list(pageSize = 3, page = 1))$rows %==% 4:6)
  (run_page(d, list(pageSize = 3, page = 2))$rows %==% 7L)
  # the pager's "last" step asks for a page past the end
  p = run_page(d, list(pageSize = 3, page = 99))
  (p$rows %==% 7L)
  (p$page %==% 2L)
  # a filter can leave fewer rows than the current page holds
  p = run_page(d, list(pageSize = 3, page = 2, term = 'x < 3'))
  (p$rows %==% 1:2)
  (p$page %==% 0L)
  # no matches at all: the first page of nothing
  p = run_page(d, list(pageSize = 3, page = 2, term = 'zzz'))
  (p$rows %==% integer(0))
  (p$page %==% 0L)
})

# End-to-end in a headless browser: the extension must find the table lt.js
# already mounted, wire the controls, and re-render <tbody> on interaction.

# Render `x`, run `js` once the page has loaded (with the table element bound to
# `t`), then read `expr` back: the browser stamps it on <body> and we parse it
# out of the DOM dump. All assets are inlined, so lt.js builds the table and
# lt-interactive.js enhances it before the load event fires.
lti_eval = function(x, expr, js = '') {
  code = sprintf(
    'var t = document.querySelector(".lt-table");%s;document.body.dataset.out = (%s)',
    js, expr
  )
  html = sub('</head>', sprintf(
    '<script>addEventListener("load", function() {%s})</script></head>', code
  ), format(x, fragment = FALSE), fixed = TRUE)
  f = tempfile(fileext = '.html')
  on.exit(unlink(f), add = TRUE)
  xfun::write_utf8(html, f)
  # the full document, not a fragment: the value is stamped on <body> itself
  dom = xfun::browser_dom(f)
  m = regmatches(dom, regexec('data-out="([^"]*)"', dom))[[1]]
  if (length(m) != 2L) stop('failed to read the probe value from the browser')
  m[2]
}

# the first-column text of each rendered body row, in rendered order
lti_rows = function(x, js = '') strsplit(lti_eval(
  x, '[...t.querySelectorAll("tbody tr")].map(r => r.children[0].textContent).join("|")',
  js
), '|', fixed = TRUE)[[1]]

itbl = function(...) lt(data.frame(name = sym, n = c(5, 12, 3, 8))) |> lt_interactive(...)

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

assert("the search box filters the rendered rows", {
  x = itbl()
  # a `change` event (Enter, or leaving the box) applies the term immediately,
  # bypassing the debounce that `input` events go through
  find = function(term) sprintf(
    'var i = t.closest(".lt-wrap").previousElementSibling;
     i.value = %s; i.dispatchEvent(new Event("change"))', xfun::tojson(term)
  )
  (lti_rows(x, find('rash')) %==% 'Rash')
  (lti_rows(x, find('!rash')) %==% c("Nausea", "Headache", "Itch"))
  (lti_rows(x, find('x > 5')) %==% c("Nausea", "Itch"))
  # no matches: a single placeholder row spanning the table
  (lti_eval(x, 't.querySelectorAll("tbody .lti-empty td").length', find('zzz')) %==% '1')
  (lti_eval(x, 't.querySelector("tbody td").colSpan', find('zzz')) %==% '2')
})

assert("a column filter box filters on its own column", {
  x = itbl(filter = TRUE)
  set = function(i, term) sprintf(
    'var i = t.querySelectorAll(".lti-filters input")[%d];
     i.value = %s; i.dispatchEvent(new Event("change"))', i, xfun::tojson(term)
  )
  (lti_rows(x, set(0, 'a')) %==% c("Rash", "Nausea", "Headache"))
  (lti_rows(x, set(1, 'x > 5')) %==% c("Nausea", "Itch"))
  # a character vector picks the columns that get a box
  (lti_eval(itbl(filter = 'n'), 't.querySelectorAll(".lti-filters input").length') %==% '1')
  # off by default, and the filter row lives in <thead>, so it survives a
  # re-render of <tbody>
  (lti_eval(itbl(), 't.querySelectorAll(".lti-filters").length') %==% '0')
  (lti_eval(x, 't.querySelectorAll("thead .lti-filters input").length', set(0, 'a')) %==% '2')
})

assert("the pager shows one page of rows at a time", {
  x = itbl(paginate = TRUE, page_size = 2)
  click = function(i) sprintf(
    'document.querySelectorAll(".lti-pager button")[%d].click()', i
  )
  (lti_rows(x) %==% c("Rash", "Nausea"))
  (lti_rows(x, click(2)) %==% c("Headache", "Itch"))                    # next
  (lti_rows(x, paste(click(2), click(1), sep = ';')) %==% c("Rash", "Nausea"))  # prev
  (lti_rows(x, click(3)) %==% c("Headache", "Itch"))                    # last
  (lti_rows(x, paste(click(3), click(0), sep = ';')) %==% c("Rash", "Nausea"))  # first
  # the readout counts the rows, and the arrows are dead at the ends
  pos = 'document.querySelector(".lti-pos").textContent'
  (lti_eval(x, pos) %==% '1–2 / 4')
  (lti_eval(x, pos, click(2)) %==% '3–4 / 4')
  dis = 'document.querySelectorAll(".lti-pager button")'
  (lti_eval(x, sprintf('[...%s].map(b => +b.disabled).join("")', dis)) %==% '1100')
  (lti_eval(x, sprintf('[...%s].map(b => +b.disabled).join("")', dis), click(2)) %==% '0011')
})

assert("the page size selector re-pages, and searching returns to page 1", {
  x = itbl(paginate = TRUE, page_size = 2, page_size_options = c(2, 4))
  size = function(v) sprintf(
    'var s = document.querySelector(".lti-pager select");
     s.value = "%s"; s.dispatchEvent(new Event("change"))', v
  )
  (lti_rows(x, size(4)) %==% sym)
  # on page 2, then a search whose matches fit on page 1
  find = 'var i = t.closest(".lt-wrap").previousElementSibling;
          i.value = "a"; i.dispatchEvent(new Event("change"))'
  (lti_rows(x, paste('document.querySelectorAll(".lti-pager button")[2].click()', find,
                     sep = ';')) %==% c("Rash", "Nausea"))
  (lti_eval(x, 'document.querySelector(".lti-pos").textContent', find) %==% '1–2 / 3')
})

assert("sort and search can be disabled individually", {
  # `n` of controls: sortable headers, search boxes
  probe = '[t.querySelectorAll(".lti-sortable").length,
            t.parentNode.parentNode.querySelectorAll("input").length].join(",")'
  (lti_eval(itbl(), probe) %==% '2,1')
  (lti_eval(itbl(sort = FALSE), probe) %==% '0,1')
  (lti_eval(itbl(search = FALSE), probe) %==% '2,0')
})

assert("a non-flat table is left static", {
  x = lt(data.frame(g = c("a", "a", "b"), v = 1:3)) |> lt_group(~ g) |>
    lt_interactive()
  (lti_eval(x, '[...t.querySelectorAll(".lti-sortable")].length') %==% '0')
})
