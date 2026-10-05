build = function(spec) {
  x = structure(spec, class = 'lt_tbl')
  # collapse to one string: a multi-value cell <title> embeds "\n" between
  # entries, which would otherwise split the (single-line) HTML into a vector
  # and hide anything after it (e.g. the footer legend) from count_str().
  paste(as.character(lt_static(x, method = 'node', css = FALSE, fragment = TRUE)),
    collapse = '\n')
}

# count non-overlapping occurrences of a fixed substring
count_str = function(x, p) {
  m = gregexpr(p, x, fixed = TRUE)[[1]]
  if (m[1] == -1L) 0L else length(m)
}

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

# End-to-end in a headless browser: the extension must find the table lt.js
# already mounted, wire the controls, and re-render <tbody> on interaction.

# Reuse one headless Chrome across all probes (navigate per call) instead of
# launching chromium per probe. Created lazily, closed when R exits. Falls back
# to the one-shot dump only where chromote is unavailable.
.browser = new.env(parent = emptyenv())

lti_session = function() {
  if (is.null(.browser$b)) {
    .browser$b = chromote::ChromoteSession$new()
    reg.finalizer(.browser, function(e) try(e$b$close(), silent = TRUE), onexit = TRUE)
  }
  .browser$b
}

# data-ready is set only after data-out, so an empty data-out (a legitimate
# result, e.g. no rows) is not mistaken for "not loaded yet"
lti_eval_cdp = function(f) {
  b = lti_session()
  b$Page$navigate(paste0('file://', normalizePath(f)), wait_ = FALSE)
  probe = 'document.body.dataset.ready === "1" ? (document.body.dataset.out ?? "") : null'
  for (i in 1:2000) {
    v = tryCatch(b$Runtime$evaluate(probe)$result$value, error = function(e) NULL)
    if (!is.null(v)) return(v)
    Sys.sleep(0.005)
  }
  stop('failed to read the probe value from the browser')
}

lti_eval_dump = function(f) {
  dom = xfun::browser_dom(f)
  m = regmatches(dom, regexec('data-out="([^"]*)"', dom))[[1]]
  if (length(m) != 2L) stop('failed to read the probe value from the browser')
  m[2]
}

# Render `x`, run `js` once the page has loaded (with the table element bound to
# `t`), then read `expr` back: the browser stamps it on <body> and we read it
# back. All assets are inlined, so lt.js builds the table and lt-interactive.js
# enhances it before the load event fires.
lti_eval = function(x, expr, js = '') {
  code = sprintf(
    'var t = document.querySelector(".lt-table");%s;document.body.dataset.out = (%s);document.body.dataset.ready = "1"',
    js, expr
  )
  html = sub('</head>', sprintf(
    '<script>addEventListener("load", function() {%s})</script></head>', code
  ), format(x, fragment = FALSE), fixed = TRUE)
  f = tempfile(fileext = '.html')
  on.exit(unlink(f), add = TRUE)
  xfun::write_utf8(html, f)
  # the full document, not a fragment: the value is stamped on <body> itself
  if (xfun::loadable('chromote')) lti_eval_cdp(f) else lti_eval_dump(f)
}

# the first-column text of each rendered body row, in rendered order
lti_rows = function(x, js = '') strsplit(lti_eval(
  x, '[...t.querySelectorAll("tbody tr")].map(r => r.children[0].textContent).join("|")',
  js
), '|', fixed = TRUE)[[1]]

itbl = function(...) lt(data.frame(name = sym, n = c(5, 12, 3, 8))) |> lt_interactive(...)

# a column's rendered cell text, column `ci` (0-based), in rendered row order
lti_col = function(x, ci, js = '') strsplit(lti_eval(x, sprintf(
  '[...t.querySelectorAll("tbody tr")].map(r => r.children[%d].textContent).join("|")', ci
), js), '|', fixed = TRUE)[[1]]
