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
let view = int.computeView(spec, disp, state), paged = "pageSize" in state;
if (paged) view = int.pageSlice(view, state);
process.stdout.write(view.join(",") + (paged ? "|" + state.page : ""));
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

# `state$sort` is a list of {col, dir} keys applied in order; `k()` builds one
# and `by()` wraps a set of them into a sort state.
k = function(col, dir = 'asc') list(col = col, dir = dir)
by = function(...) list(sort = list(...))

assert("numeric sort orders by raw value; nulls sort last both directions", {
  d = list(name = sym, n = c(5, 12, 3, 8))
  (run_view(d, by(k('n', 'asc'))) %==% c(3L, 1L, 4L, 2L))
  (run_view(d, by(k('n', 'desc'))) %==% c(2L, 4L, 1L, 3L))
  d2 = list(n = c(5, NA, 3))
  (run_view(d2, by(k('n', 'asc'))) %==% c(3L, 1L, 2L))
  (run_view(d2, by(k('n', 'desc'))) %==% c(1L, 3L, 2L))
})

assert("string columns sort locale-aware (case-insensitive letter order)", {
  d = list(g = c("banana", "Apple", "cherry"))
  (run_view(d, by(k('g', 'asc'))) %==% c(2L, 1L, 3L))
})

assert("several sort keys break ties in order", {
  d = list(g = c("a", "a", "b", "b"), v = c(2, 1, 1, 2))
  # g ascending, then v descending within each group
  (run_view(d, by(k('g'), k('v', 'desc'))) %==% c(1L, 2L, 4L, 3L))
  # g ascending, then v ascending
  (run_view(d, by(k('g'), k('v'))) %==% c(2L, 1L, 3L, 4L))
  # a later key only decides rows the earlier ones tie on
  (run_view(d, by(k('v'), k('g'))) %==% c(2L, 3L, 1L, 4L))
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
  (run_view(d, c(list(term = 'a'), by(k('n', 'desc')))) %==% c(2L, 1L, 3L))
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
  # a page size of 0 (Inf in R) is one page holding every row
  p = run_page(d, list(pageSize = 0, page = 2))
  (p$rows %==% 1:7)
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

# a column's rendered cell text, column `ci` (0-based), in rendered row order
lti_col = function(x, ci, js = '') strsplit(lti_eval(x, sprintf(
  '[...t.querySelectorAll("tbody tr")].map(r => r.children[%d].textContent).join("|")', ci
), js), '|', fixed = TRUE)[[1]]

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

assert("the search box filters the rendered rows", {
  x = itbl()
  # a `change` event (Enter, or leaving the box) applies the term immediately,
  # bypassing the debounce that `input` events go through
  find = function(term) sprintf(
    'var i = t.querySelector(".lti-search");
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
  x = itbl(pager = 2)
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
  # a single page size offers no selector
  (lti_eval(x, 'document.querySelectorAll(".lti-pager select").length') %==% '0')
})

assert("paging is on by default and can be turned off", {
  (lti_eval(itbl(), 'document.querySelector(".lti-pos").textContent') %==% '1–4 / 4')
  (lti_eval(itbl(pager = FALSE),
            'document.querySelectorAll(".lti-pager").length') %==% '0')
})

assert("a page size of Inf puts every row on one page", {
  x = itbl(pager = c(2, Inf))
  # the selector offers it as a symbol, since there is no count to show
  (lti_eval(x, '[...document.querySelectorAll(".lti-pager option")].map(o => o.textContent).join(",")')
   %==% '2,∞')
  pick = 'var s = document.querySelector(".lti-pager select");
          s.value = "0"; s.dispatchEvent(new Event("change"))'
  (lti_rows(x) %==% c("Rash", "Nausea"))
  (lti_rows(x, pick) %==% sym)
  (lti_eval(x, 'document.querySelector(".lti-pos").textContent', pick) %==% '1–4 / 4')
  # one page: every arrow is dead
  (lti_eval(x, '[...document.querySelectorAll(".lti-pager button")].map(b => +b.disabled).join("")',
            pick) %==% '1111')
})

assert("the page size selector re-pages, and searching returns to page 1", {
  x = itbl(pager = c(2, 4))
  size = function(v) sprintf(
    'var s = document.querySelector(".lti-pager select");
     s.value = "%s"; s.dispatchEvent(new Event("change"))', v
  )
  (lti_rows(x, size(4)) %==% sym)
  # on page 2, then a search whose matches fit on page 1
  find = 'var i = t.querySelector(".lti-search");
          i.value = "a"; i.dispatchEvent(new Event("change"))'
  (lti_rows(x, paste('document.querySelectorAll(".lti-pager button")[2].click()', find,
                     sep = ';')) %==% c("Rash", "Nausea"))
  (lti_eval(x, 'document.querySelector(".lti-pos").textContent', find) %==% '1–2 / 3')
})

assert("sort and search can be disabled individually", {
  # `n` of controls: sortable headers, search boxes
  probe = '[t.querySelectorAll(".lti-sortable").length,
            t.querySelectorAll(".lti-search").length].join(",")'
  (lti_eval(itbl(), probe) %==% '2,1')
  (lti_eval(itbl(sort = FALSE), probe) %==% '0,1')
  (lti_eval(itbl(search = FALSE), probe) %==% '2,0')
})

assert("the controls are rows of the table, so they match its width", {
  x = itbl(filter = TRUE)
  # nothing is placed beside the table: the core wrapper holds the table alone
  (lti_eval(x, 't.parentNode.className') %==% 'lt-wrap')
  (lti_eval(x, 't.parentNode.children.length') %==% '1')
  # the search box and the pager each span every column
  (lti_eval(x, 't.tHead.rows[0].className') %==% 'lti-head')
  (lti_eval(x, 't.querySelector(".lti-head td").colSpan') %==% '2')
  (lti_eval(x, 't.querySelector(".lti-pager-row td").colSpan') %==% '2')
  # a table with notes keeps them above the pager, so their borders still apply
  y = lt(data.frame(a = 1:3)) |> lt_note('hi') |> lt_interactive(pager = 2)
  (lti_eval(y, '[...t.tFoot.rows].map(r => r.className).join(",")') %==%
     'lt-source-note,lti-pager-row')
})

# Widths of the header cells that carry a resize grip, the table width, and a
# drag of grip `i` by `dx` px (the pointer events a real drag delivers: down on
# the grip, then move/up anywhere).
MEASURE = 'var th = i => t.querySelectorAll(".lti-resizer")[i].parentNode;
  var w = i => th(i).getBoundingClientRect().width;
  var tw = () => t.getBoundingClientRect().width;
  var w0 = w(0), w1 = w(1), t0 = tw();'

drag = function(i, dx) sprintf(
  'var g = t.querySelectorAll(".lti-resizer")[%d];
   var x = g.getBoundingClientRect().right;
   var ev = (n, cx) => new PointerEvent(n, {bubbles: true, cancelable: true, clientX: cx});
   g.dispatchEvent(ev("pointerdown", x));
   document.dispatchEvent(ev("pointermove", x + (%s)));
   document.dispatchEvent(ev("pointerup", x + (%s)));', i, dx, dx
)

assert("dragging a column edge resizes that column, and the table with it", {
  x = itbl(resize = TRUE)
  # one grip per column, in the header cells, and one <col> to carry each width
  (lti_eval(x, 't.querySelectorAll("thead th .lti-resizer").length') %==% '2')
  (lti_eval(x, 't.querySelectorAll("colgroup col").length') %==% '2')
  # the first column grows by the drag distance; the second is left alone, so
  # the table grows by as much and the wrapper can scroll to it
  probe = '[w(0) - w0, w(1) - w1, tw() - t0].map(Math.round).join(",")'
  (lti_eval(x, probe, paste(MEASURE, drag(0, 40))) %==% '40,0,40')
  (lti_eval(x, 't.className', drag(0, 40)) %==% 'lt-table lti-fixed')
  # the widths live outside <tbody>, so sorting (which re-renders it) keeps them
  (lti_eval(x, probe, paste(MEASURE, drag(0, 40), 'th(1).click()')) %==% '40,0,40')
})

assert("a column cannot be dragged away, and a double-click fits it again", {
  x = itbl(resize = TRUE)
  # dragging far to the left stops at the minimum width
  (lti_eval(x, 't.querySelectorAll("col")[0].style.width', drag(0, -1000)) %==% '24px')
  # a double-click on the grip restores the column's content width
  fit = paste(MEASURE, drag(0, -1000),
              't.querySelector(".lti-resizer").dispatchEvent(
                 new MouseEvent("dblclick", {bubbles: true}))')
  (lti_eval(x, 'Math.round(w(0) - w0)', fit) %==% '0')
})

assert("resizing is off by default", {
  (lti_eval(itbl(), 't.querySelectorAll(".lti-resizer").length') %==% '0')
  (lti_eval(itbl(), 't.className') %==% 'lt-table')
})

# whether header `ti` (0-based) and its first body cell are hidden
th_hidden = function(ti) sprintf('t.querySelectorAll("thead th")[%d].hidden', ti)
cell_hidden = function(ti) sprintf(
  't.querySelector("tbody tr").children[%d].hidden', ti)
# toggle the menu box for column `ti` to `on`, as a single real click does. (A
# scripted click() on a box nested in its <label> double-fires — the click
# bubbles to the label, which re-dispatches to the control — so set + change.)
set_box = function(ti, on) sprintf(
  '{var b=t.querySelectorAll(".lti-menu input")[%d];b.checked=%s;b.dispatchEvent(new Event("change"))}',
  ti, tolower(on))

assert("the column menu lists every column and hides the unchecked ones", {
  x = itbl(hide = TRUE)
  # an icon button opens a checklist with one box per column, all checked
  (lti_eval(x, 't.querySelector(".lti-cols button") ? 1 : 0') %==% '1')
  (lti_eval(x, 't.querySelectorAll(".lti-menu input").length') %==% '2')
  (lti_eval(x, '[...t.querySelectorAll(".lti-menu input")].every(b => b.checked)')
   %==% 'true')
  # unchecking a box hides that column's header and cells; the other is untouched
  off1 = set_box(1, FALSE)
  (lti_eval(x, th_hidden(1), off1) %==% 'true')
  (lti_eval(x, cell_hidden(1), off1) %==% 'true')
  (lti_eval(x, cell_hidden(0), off1) %==% 'false')
  # the hidden column stays hidden across a re-render (sorting the other column)
  sortN = 'document.querySelectorAll("thead th")[0].click()'
  (lti_eval(x, cell_hidden(1), paste(off1, sortN, sep = ';')) %==% 'true')
  # re-checking restores it
  (lti_eval(x, th_hidden(1), paste(off1, set_box(1, TRUE), sep = ';')) %==% 'false')
})

assert("hide = column names starts those columns hidden; the menu still lists all", {
  x = itbl(hide = 'n')
  (lti_eval(x, 't.querySelectorAll(".lti-menu input").length') %==% '2')
  # the named column starts unchecked and hidden; the other starts shown
  (lti_eval(x, 't.querySelectorAll(".lti-menu input")[1].checked') %==% 'false')
  (lti_eval(x, th_hidden(1)) %==% 'true')
  (lti_eval(x, cell_hidden(1)) %==% 'true')
  (lti_eval(x, th_hidden(0)) %==% 'false')
  # no menu at all by default
  (lti_eval(itbl(), 't.querySelectorAll(".lti-cols").length') %==% '0')
})

assert("with resize on, hiding a column also drops its <col> (fixed layout)", {
  # the body cells alone would leave a gap in a fixed-layout table; the <col>
  # must be hidden too for the column to collapse
  x = itbl(hide = TRUE, resize = TRUE)
  off1 = set_box(1, FALSE)
  (lti_eval(x, 't.querySelectorAll("col")[1].hidden', off1) %==% 'true')
  (lti_eval(x, th_hidden(1), off1) %==% 'true')
})

assert("a table rendered on demand is enhanced like one rendered in place", {
  # forestly's lazy path: a spec turned into a table long after the page loaded
  x = itbl(pager = 2)
  make = 'var t2 = LT.render(document.body.appendChild(
            document.createElement("div")), t._ltSpec)'
  (lti_eval(x, 't2.className', make) %==% 'lt-table')
  # the new table got its own controls and its own first page
  (lti_eval(x, 't2.querySelectorAll(".lti-sortable").length', make) %==% '2')
  rows = '[...t2.querySelectorAll("tbody tr")].map(r => r.children[0].textContent).join("|")'
  (lti_eval(x, rows, make) %==% 'Rash|Nausea')
  # its state is its own: sorting it leaves the table it was built from alone
  sort2 = paste(make, 't2.querySelectorAll("thead th")[1].click()', sep = ';')
  (lti_eval(x, rows, sort2) %==% 'Headache|Rash')
  (lti_eval(
    x, '[...t.querySelectorAll("tbody tr")].map(r => r.children[0].textContent).join("|")',
    sort2
  ) %==% 'Rash|Nausea')
})

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
  srt = paste(open0, 'document.querySelectorAll("thead th")[1].click()', sep = ';')
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

assert("lt_errorbar renders SVG only for the current page (deferred)", {
  # six rows, paged three at a time: the SVG is drawn in the browser, so only
  # the visible page's rows carry one -- the payload ships numbers, not SVG
  n = 6
  x = lt(data.frame(
    est = seq(0.1, 0.6, length.out = n),
    lo  = seq(0.0, 0.5, length.out = n),
    hi  = seq(0.2, 0.7, length.out = n)
  )) |>
    lt_errorbar(est ~ lo + hi, ref = 0) |>
    lt_interactive(pager = 3)
  (lti_eval(x, 't.querySelectorAll(".lt-eb").length') %==% '3')
  # paging to the next page re-renders SVG for that page's rows, not all six
  next_pg = 't.querySelector(".lti-pager button[aria-label=\\"Next\\"]").click()'
  (lti_eval(x, 't.querySelectorAll(".lt-eb").length', next_pg) %==% '3')
})

assert("lt_sparkline draws a line/bar SVG per row from the series", {
  # a list-column of series: one <path> per row; a NULL in the series breaks the
  # line into two subpaths (two "M" move commands)
  d = data.frame(g = c("a", "b"))
  d$s = list(c(1, 2, 3, 4), c(5, NA, 7, 8))
  x = lt(d) |> lt_sparkline(~ s)
  (lti_eval(x, 't.querySelectorAll(".lt-spark path").length') %==% '2')
  (lti_eval(x,
    '[...t.querySelectorAll(".lt-spark path")].map(p=>(p.getAttribute("d").match(/M/g)||[]).length).join(",")')
   %==% '1,2')
  # bars read across several columns: four values -> four <rect> per row
  m = data.frame(a = c(1, 4), b = c(2, 3), c = c(3, 2), d = c(4, 1))
  xb = lt(m) |> lt_sparkline(~ a + b + c + d, type = "bar")
  (lti_eval(xb, 't.querySelectorAll("tbody .lt-spark rect").length') %==% '8')
})

assert("lt_dotplot draws one colored dot per column with a footer legend", {
  d = data.frame(g = c("a", "b"), x = c(1, 4), y = c(2, 3), z = c(3, 2))
  x = lt(d) |> lt_dotplot(~ x + y + z, color = c("red", "green", "blue"))
  # three columns over two rows -> six dots, each colored by its column. The
  # color is a fill= attribute, which the default stylesheet leaves alone
  # (:not([fill])) but user CSS can still override
  (lti_eval(x, 't.querySelectorAll("tbody .lt-dot circle").length') %==% '6')
  (lti_eval(x, 't.querySelector("tbody .lt-dot circle").getAttribute("fill")')
   %==% 'red')
  # a colored plot keys the colors in a footer legend (one swatch per column)
  (lti_eval(x, 't.querySelectorAll(".lt-dot-legend i").length') %==% '3')
  # monochrome by default: dots carry no fill override and no legend is drawn
  xm = lt(d) |> lt_dotplot(~ x + y + z)
  (lti_eval(xm, 't.querySelector("tbody .lt-dot circle").hasAttribute("fill")')
   %==% 'false')
  (lti_eval(xm, 't.querySelectorAll(".lt-dot-legend").length') %==% '0')
})

assert("lt-plot.js re-renders a table core built before the module loaded", {
  # The litedown/knitr failure mode: an earlier plain table pulls in lt.js, so
  # it loads (and builds this table) before lt-plot.js registers the errorbar
  # renderer. Load core *before* the module here and confirm the module's
  # on-load refresh draws the error bars that the first build lacked.
  spec = list(
    data = list(est = c(0.5, 0.2), lo = c(0, 0.1), hi = c(1, 0.3)),
    ops = list(list(type = "errorbar", columns = c("est", "lo", "hi"),
      min = 0, max = 1, width = 80, height = 16))
  )
  x = structure(spec, class = 'lt_tbl')
  core = paste(read_asset('lt.js'), collapse = '\n')
  plotjs = paste(read_asset('lt-plot.js'), collapse = '\n')
  sb = paste(spec_block(x), collapse = '\n')
  html = paste0(
    "<!DOCTYPE html><html><head><meta charset='utf-8'>",
    "<script>", core, "</script></head><body>", sb,
    "<script>", plotjs, "</script>",
    "<script>addEventListener('load',function(){",
    "document.body.dataset.out=document.querySelectorAll('.lt-eb').length})",
    "</script></body></html>"
  )
  f = tempfile(fileext = '.html'); on.exit(unlink(f), add = TRUE)
  xfun::write_utf8(html, f)
  dom = xfun::browser_dom(f)
  m = regmatches(dom, regexec('data-out="([^"]*)"', dom))[[1]]
  (m[2] %==% '2')  # one error-bar SVG per row, drawn by the late refresh
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
