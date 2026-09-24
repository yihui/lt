# Exercise the interactive plugin's view pipeline (search + sort) in Node.js.
# The runner loads core lt.js and lt-interactive.js into one context, then calls
# LT.plugins.interactive.computeView on a spec/display/state supplied as JSON,
# and prints the resulting 1-based row indices (spec._viewRows) as a CSV list.

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
const view = ctx.LT.plugins.interactive.computeView(spec, disp, inp.state || {});
process.stdout.write(view.join(","));
'

run_view = function(data, state = list(), disp = NULL) {
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
  out = paste(out, collapse = '')
  if (!nzchar(out)) integer(0) else as.integer(strsplit(out, ',')[[1]])
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
