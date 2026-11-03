# Inline plots: error bars and dot plots rendered statically in Node.js, plus
# deferred rendering of error bars, sparklines, dot plots in browser.

assert("lt_errorbar renders an inline SVG point-and-bar on a shared scale", {
  spec = list(
    data = list(est = c(0.5, 0.2), lo = c(0, 0.1), hi = c(1, 0.3)),
    ops = list(list(type = "errorbar", columns = I("est"), lowers = I("lo"),
      uppers = I("hi"), min = 0, max = 1, ref = 0, width = 80, height = 16))
  )
  html = build(spec)
  # one SVG per row in value column; lo/hi columns still render as data
  (count_str(html, '<svg class="lt-eb"') %==% 2L)
  # scale inset by 4px pad each side (W = 80 -> inner span 72), so
  # points/bars never touch cell edge.
  # row 1: est 0.5 -> cx 40 (cy = height/2 = 8); bar from lo 0 (x 4) to hi 1 (x 76)
  (has_match(html, I('<circle cx="40" cy="8"')))
  (has_match(html, I('x1="4" y1="8" x2="76" y2="8"')))
  # short vertical end caps at both bar ends (y = 8 ± cap, cap = 3)
  (has_match(html, I('x1="4" y1="5" x2="4" y2="11"')))
  (has_match(html, I('x1="76" y1="5" x2="76" y2="11"')))
  # row 2 lands on the same scale: est 0.2 -> cx 18.4, bar 0.1..0.3 -> x 11.2..25.6
  (has_match(html, I('<circle cx="18.4" cy="8"')))
  (has_match(html, I('x1="11.2" y1="8" x2="25.6" y2="8"')))
  # vertical reference line at ref = 0 (x 4, full height)
  (has_match(html, I('class="lt-eb-ref" x1="4" y1="0" x2="4" y2="16"')))
  # numbers stay in title tooltip, not inline SVG text
  (has_match(html, I('<title>0.5 (0, 1)</title>')))
})

assert("lt_errorbar axis = TRUE draws one shared axis in the footer", {
  spec = list(
    data = list(est = c(0.5, 0.2), lo = c(0, 0.1), hi = c(1, 0.3)),
    ops = list(list(type = "errorbar", columns = I("est"), lowers = I("lo"),
      uppers = I("hi"), min = 0, max = 1, ref = 0, width = 80, height = 16,
      axis = TRUE, axis_label = "Effect"))
  )
  html = build(spec)
  # one axis SVG total (not per row), in footer
  (count_str(html, '<svg class="lt-eb-axis"') %==% 1L)
  (has_match(html, I("<tfoot")))
  # "nice" ticks for [0, 1] step 0.2; end labels inset by 4px pad, mid
  # tick (0.4 -> x 32.8) middle-anchored
  (has_match(html, I('<text x="4" y="15" text-anchor="start">0</text>')))
  (has_match(html, I('<text x="76" y="15" text-anchor="end">1</text>')))
  (has_match(html, I('<text x="32.8" y="15" text-anchor="middle">0.4</text>')))
  # same ticks drive stretched in-cell gridline background (one per row)
  (count_str(html, 'class="lt-eb-grid-bg"') %==% 2L)
  # axis caption centered below ticks
  (has_match(html, I('class="lt-eb-axis-label" x="40" y="28" text-anchor="middle">Effect</text>')))

  # tick count adapts to width so labels do not crowd: narrow axis keeps only
  # endpoints, wide one shows full 0.2 step
  narrow = build(list(data = list(est = 0.5, lo = 0, hi = 1),
    ops = list(list(type = "errorbar", columns = I("est"), lowers = I("lo"),
      uppers = I("hi"), min = 0, max = 1, width = 40, height = 16, axis = TRUE))))
  wide = build(list(data = list(est = 0.5, lo = 0, hi = 1),
    ops = list(list(type = "errorbar", columns = I("est"), lowers = I("lo"),
      uppers = I("hi"), min = 0, max = 1, width = 300, height = 16, axis = TRUE))))
  (count_str(narrow, "</text>") %==% 2L)
  (isTRUE(count_str(wide, "</text>") > count_str(narrow, "</text>")) %==% TRUE)
})

assert("lt_errorbar stacks several colored series with a footer legend", {
  spec = list(
    data = list(e1 = 0.5, l1 = 0.2, u1 = 0.8, e2 = 0.3, l2 = 0.1, u2 = 0.5),
    ops = list(list(type = "errorbar", columns = c("e1", "e2"),
      lowers = c("l1", "l2"), uppers = c("u1", "u2"),
      colors = c("#1b9e77", "#d95f02"), labels = c("A", "B"),
      min = 0, max = 1, width = 80, height = 28, axis = TRUE))
  )
  html = build(spec)
  # one SVG for single row, both series stacked at distinct y
  # (n = 2 at H = 28 -> rows at round(28/3) = 9 and round(56/3) = 19)
  (count_str(html, '<svg class="lt-eb"') %==% 1L)
  # each series takes own color, as fill= (point) / stroke= (bar) attr
  (has_match(html, I('<circle fill="#1b9e77" cx="40" cy="9"')))
  (has_match(html, I('<circle fill="#d95f02" cx="25.6" cy="19"')))
  (has_match(html, I('<line stroke="#1b9e77" x1="18.4" y1="9" x2="61.6" y2="9"')))
  (has_match(html, I('<line stroke="#d95f02" x1="11.2" y1="19" x2="40" y2="19"')))
  # tooltip keys each series by label
  (has_match(html, I('A: 0.5 (0.2, 0.8)')))
  # single footer legend keyed by color + label (not per row)
  (count_str(html, 'class="lt-plot-legend"') %==% 1L)
  (has_match(html, I('background:#1b9e77"></i>A</span>')))
  (has_match(html, I('background:#d95f02"></i>B</span>')))
})

assert("lt_dotplot stagger puts each column's dot on its own vertical track", {
  base = list(data = list(a = 1, b = 2, c = 3))
  op = list(type = "dotplot", columns = c("a", "b", "c"),
    min = 0, max = 4, width = 80, height = 40)
  # default: all three dots share mid-line (cy = height/2 = 20)
  flat = build(c(base, list(ops = list(op))))
  (count_str(flat, 'cy="20"') %==% 3L)
  # stagger: evenly spaced tracks round((i+1)/(n+1)*H) -> 10, 20, 30
  staggered = build(c(base, list(ops = list(c(op, list(stagger = TRUE))))))
  (has_match(staggered, I('cy="10"')))
  (has_match(staggered, I('cy="30"')))
  (count_str(staggered, 'cy="20"') %==% 1L)
})

assert("lt_errorbar/lt_dotplot `into` draws into a runtime-synthesized column", {
  # `into` names target column not in data: `add_col` op makes runtime
  # materialize it, draw plot into it, leave value columns as text. `fig`
  # is that column.
  spec = list(
    data = list(est = c(0.5, 0.2), lo = c(0, 0.1), hi = c(1, 0.3)),
    ops = list(
      list(type = "add_col", column = "fig"),
      list(type = "errorbar", columns = I("est"), lowers = I("lo"),
        uppers = I("hi"), into = "fig", min = 0, max = 1, width = 80,
        height = 16))
  )
  html = build(spec)
  # synthesized column has header and one SVG per row
  (has_match(html, I(">fig</th>")))
  (count_str(html, '<svg class="lt-eb"') %==% 2L)
  # value column still renders numbers as data cells (not consumed)
  (has_match(html, I(">0.5</td>")))
  (has_match(html, I(">0.2</td>")))
  # dot plot into (missing) dedicated column behaves the same
  dp = build(list(
    data = list(a = c(1, 2), b = c(3, 4)),
    ops = list(
      list(type = "add_col", column = "plot"),
      list(type = "dotplot", columns = c("a", "b"), into = "plot",
        min = 0, max = 4, width = 80, height = 16))
  ))
  (has_match(dp, I(">plot</th>")))
  (count_str(dp, '<svg class="lt-dot"') %==% 2L)
  (has_match(dp, I(">1</td>")))
  (has_match(dp, I(">4</td>")))
})

assert("lt_errorbar renders SVG only for the current page (deferred)", {
  # six rows, paged three at a time: SVG drawn in browser, so only visible
  # page's rows carry one -- payload ships numbers, not SVG
  n = 6
  x = lt(data.frame(
    est = seq(0.1, 0.6, length.out = n),
    lo  = seq(0.0, 0.5, length.out = n),
    hi  = seq(0.2, 0.7, length.out = n)
  )) |>
    lt_errorbar(est ~ lo + hi, ref = 0) |>
    lt_interactive(pager = 3)
  (lti_eval(x, 't.querySelectorAll(".lt-eb").length') %==% '3')
  # next page re-renders SVG for that page's rows, not all six
  next_pg = 't.querySelector(".lti-pager button[aria-label=\\"Next\\"]").click()'
  (lti_eval(x, 't.querySelectorAll(".lt-eb").length', next_pg) %==% '3')
})

assert("lt_sparkline draws a line/bar SVG per row from the series", {
  # list-column of series: one <path> per row; NULL in series breaks
  # line into two subpaths (two "M" move commands)
  d = data.frame(g = c("a", "b"))
  d$s = list(c(1, 2, 3, 4), c(5, NA, 7, 8))
  x = lt(d) |> lt_sparkline(~ s)
  (lti_eval(x, 't.querySelectorAll(".lt-spark path").length') %==% '2')
  (lti_eval(x,
    '[...t.querySelectorAll(".lt-spark path")].map(p=>(p.getAttribute("d").match(/M/g)||[]).length).join(",")')
   %==% '1,2')
  # bars read across columns: four values -> four <rect> per row
  m = data.frame(a = c(1, 4), b = c(2, 3), c = c(3, 2), d = c(4, 1))
  xb = lt(m) |> lt_sparkline(~ a + b + c + d, type = "bar")
  (lti_eval(xb, 't.querySelectorAll("tbody .lt-spark rect").length') %==% '8')
})

assert("lt_dotplot draws one colored dot per column with a footer legend", {
  d = data.frame(g = c("a", "b"), x = c(1, 4), y = c(2, 3), z = c(3, 2))
  x = lt(d) |> lt_dotplot(~ x + y + z, color = c("red", "green", "blue"))
  # three columns over two rows -> six dots, colored by column. Color is
  # fill= attribute, which default stylesheet leaves alone (:not([fill]))
  # but user CSS can still override
  (lti_eval(x, 't.querySelectorAll("tbody .lt-dot circle").length') %==% '6')
  (lti_eval(x, 't.querySelector("tbody .lt-dot circle").getAttribute("fill")')
   %==% 'red')
  # colored plot keys colors in footer legend (one swatch per column)
  (lti_eval(x, 't.querySelectorAll(".lt-plot-legend i").length') %==% '3')
  # monochrome by default: no fill override, no legend
  xm = lt(d) |> lt_dotplot(~ x + y + z)
  (lti_eval(xm, 't.querySelector("tbody .lt-dot circle").hasAttribute("fill")')
   %==% 'false')
  (lti_eval(xm, 't.querySelectorAll(".lt-plot-legend").length') %==% '0')
})

assert("a relative width marks plot cells for auto-fitting, fixed does not", {
  spec = list(
    data = list(est = c(0.5, 0.2), lo = c(0, 0.1), hi = c(1, 0.3)),
    ops = list(list(type = "errorbar", columns = I("est"), lowers = I("lo"),
      uppers = I("hi"), min = 0, max = 1, width = 160, fit = "80%", height = 16))
  )
  html = build(spec)
  # each cell SVG flexes to given CSS width (--fw), px as floor
  (count_str(html, '<svg class="lt-eb lt-fit"') %==% 2L)
  (count_str(html, '--w:160px;--fw:80%') %==% 2L)
  # fixed width (no fit) stays plain plot, no flex class or vars
  spec$ops[[1]]$fit = NULL
  (count_str(build(spec), 'lt-fit') %==% 0L)
})

assert("an auto-fit plot is measured and redrawn to fill its column (browser)", {
  d = data.frame(term = c("A", "B"), est = c(0.2, 0.4),
                 lo = c(0, 0.2), hi = c(0.4, 0.6))
  x = lt(d) |>
    lt_errorbar(est ~ lo + hi, into = "forest", hide = FALSE, width = "100%") |>
    lt_width(forest = "320px") |> lt_interactive()
  # resizer measures (wide) column, stores pixel width on op, redraws: SVG
  # coordinate `width` is measured size, not 160px floor -- marks drawn at
  # real width, not stretched by CSS
  got = lti_eval(x, paste0(
    '[t._ltSpec.ops.find(o=>o.fit)._w,',
    ' t.querySelector(".lt-eb").getAttribute("width"),',
    ' Math.round(t.querySelector(".lt-eb").getBoundingClientRect().width)].join(",")'
  ))
  v = as.integer(strsplit(got, ",", fixed = TRUE)[[1]])
  (length(v) %==% 3L)
  (v[1] > 200)          # measured column width, well past floor
  (v[2] %==% v[1])      # coordinate width redrawn to measured width
  (v[3] > 200)          # SVG actually fills column
})

assert("an auto-fit plot tracks a column-only width change (browser)", {
  d = data.frame(term = c("A", "B"), est = c(0.2, 0.4),
                 lo = c(0, 0.2), hi = c(0.4, 0.6))
  x = lt(d) |>
    lt_errorbar(est ~ lo + hi, into = "forest", hide = FALSE, width = "100%") |>
    lt_width(forest = "320px") |> lt_interactive()
  # shrink only plot column (its <col>) -- wrapper never sees it, so wrapper
  # observer would miss it; header-cell observer must catch it. Let observer
  # + redraw settle (two frames), then compare.
  body_js = paste0(
    'var op = t._ltSpec.ops.find(o => o.fit), w0 = op._w;',
    'var ci = t._ltSpec._cols.indexOf("forest");',
    't.querySelectorAll("colgroup col")[ci].style.width = "200px";',
    # poll until redraw (observer -> rAF -> rebuild) catches up; slow runners
    # (macOS CI) need more than a fixed delay
    'var n = 0, done = function(){',
    'var sw = t.querySelector(".lt-eb").getAttribute("width");',
    'if (+sw !== op._w && ++n < 50) return setTimeout(done, 100);',
    'document.body.dataset.out = [w0, op._w, sw].join(",");',
    'document.body.dataset.ready = "1";};',
    'setTimeout(done, 100);'
  )
  html = sub('</head>', sprintf(
    '<script>addEventListener("load", function() {var t = document.querySelector(".lt-table");%s})</script></head>',
    body_js
  ), format(x, fragment = FALSE), fixed = TRUE)
  f = tempfile(fileext = '.html'); on.exit(unlink(f), add = TRUE)
  xfun::write_utf8(html, f)
  out = lti_eval_cdp(f)
  v = as.integer(strsplit(out, ",", fixed = TRUE)[[1]])
  (v[1] > 250)       # started wide (320px column)
  (v[2] < v[1])      # refit narrower after column shrank
  (v[2] < 220 && v[2] > 150)  # tracks new ~200px column
  (v[3] %==% v[2])   # redrawn: SVG coordinate width matches refit
})

assert("a fractional auto-fit width takes that fraction of the column (browser)", {
  d = data.frame(term = c("A", "B"), est = c(0.2, 0.4),
                 lo = c(0, 0.2), hi = c(0.4, 0.6))
  # list(min, width): half the column, small minimum so fraction (not
  # floor) governs at this width
  x = lt(d) |>
    lt_errorbar(est ~ lo + hi, into = "forest", hide = FALSE,
                width = list(min = 50, width = "50%")) |>
    lt_width(forest = "320px") |> lt_interactive()
  got = lti_eval(x, paste0(
    '[Math.round(t.querySelector(".lt-eb").getBoundingClientRect().width),',
    ' Math.round(t._ltHead.forest.getBoundingClientRect().width)].join(",")'
  ))
  v = as.integer(strsplit(got, ",", fixed = TRUE)[[1]])
  # SVG is ~half column width (slack for cell padding/border)
  (v[1] > 0.4 * v[2])
  (v[1] < 0.6 * v[2])
})

assert("a plot refit keeps the current page, not resetting to the first (browser)", {
  d = data.frame(term = LETTERS[1:6], est = seq(.1, .6, length.out = 6),
                 lo = seq(0, .5, length.out = 6), hi = seq(.2, .7, length.out = 6))
  x = lt(d) |>
    lt_errorbar(est ~ lo + hi, into = "forest", hide = FALSE, width = "100%") |>
    lt_width(forest = "320px") |> lt_interactive(pager = 3)
  # go to page 2 (rows D, E, F), then refit plot by shrinking its column;
  # refit must re-render in place, keeping the page
  body_js = paste0(
    't.querySelector(".lti-pager button[aria-label=\\"Next\\"]").click();',
    'var ci = t._ltSpec._cols.indexOf("forest");',
    't.querySelectorAll("colgroup col")[ci].style.width = "200px";',
    'setTimeout(function(){',
    'document.body.dataset.out = [...t.querySelectorAll("tbody tr")]',
    '.map(r => r.children[0].textContent).join("");',
    'document.body.dataset.ready = "1";}, 120);'
  )
  html = sub('</head>', sprintf(
    '<script>addEventListener("load", function() {var t = document.querySelector(".lt-table");%s})</script></head>',
    body_js
  ), format(x, fragment = FALSE), fixed = TRUE)
  f = tempfile(fileext = '.html'); on.exit(unlink(f), add = TRUE)
  xfun::write_utf8(html, f)
  out = lti_eval_cdp(f)
  (out %==% "DEF")  # still page 2, not reset to "ABC"
})

assert("lt-plot.js re-renders a table core built before the module loaded", {
  # litedown/knitr failure mode: earlier plain table pulls in lt.js, so it
  # loads (and builds this table) before lt-plot.js registers errorbar
  # renderer. Load core *before* module and confirm module's on-load
  # refresh draws error bars the first build lacked.
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
  (m[2] %==% '2')  # one error-bar SVG per row, drawn by late refresh
})
