# Inline plots: error bars and dot plots rendered statically in Node.js, plus
# deferred rendering of error bars, sparklines, and dot plots in the browser.

assert("lt_errorbar renders an inline SVG point-and-bar on a shared scale", {
  spec = list(
    data = list(est = c(0.5, 0.2), lo = c(0, 0.1), hi = c(1, 0.3)),
    ops = list(list(type = "errorbar", columns = I("est"), lowers = I("lo"),
      uppers = I("hi"), min = 0, max = 1, ref = 0, width = 80, height = 16))
  )
  html = build(spec)
  # one SVG per row in the value column; the lo/hi columns still render as data
  (count_str(html, '<svg class="lt-eb"') %==% 2L)
  # the scale is inset by a 4px pad on each side (W = 80 -> inner span 72), so
  # points/bars never touch the cell edge.
  # row 1: est 0.5 -> cx 40 (cy = height/2 = 8); bar from lo 0 (x 4) to hi 1 (x 76)
  (grepl('<circle cx="40" cy="8"', html, fixed = TRUE) %==% TRUE)
  (grepl('x1="4" y1="8" x2="76" y2="8"', html, fixed = TRUE) %==% TRUE)
  # short vertical end caps at both ends of the bar (y = 8 ± cap, cap = 3)
  (grepl('x1="4" y1="5" x2="4" y2="11"', html, fixed = TRUE) %==% TRUE)
  (grepl('x1="76" y1="5" x2="76" y2="11"', html, fixed = TRUE) %==% TRUE)
  # row 2 lands on the same scale: est 0.2 -> cx 18.4, bar 0.1..0.3 -> x 11.2..25.6
  (grepl('<circle cx="18.4" cy="8"', html, fixed = TRUE) %==% TRUE)
  (grepl('x1="11.2" y1="8" x2="25.6" y2="8"', html, fixed = TRUE) %==% TRUE)
  # a vertical reference line at ref = 0 (x 4, full height)
  (grepl('class="lt-eb-ref" x1="4" y1="0" x2="4" y2="16"', html, fixed = TRUE) %==% TRUE)
  # the numbers stay in the title tooltip, not shipped as inline SVG text
  (grepl('<title>0.5 (0, 1)</title>', html, fixed = TRUE) %==% TRUE)
})

assert("lt_errorbar axis = TRUE draws one shared axis in the footer", {
  spec = list(
    data = list(est = c(0.5, 0.2), lo = c(0, 0.1), hi = c(1, 0.3)),
    ops = list(list(type = "errorbar", columns = I("est"), lowers = I("lo"),
      uppers = I("hi"), min = 0, max = 1, ref = 0, width = 80, height = 16,
      axis = TRUE, axis_label = "Effect"))
  )
  html = build(spec)
  # one axis SVG total (not one per row), in the footer
  (count_str(html, '<svg class="lt-eb-axis"') %==% 1L)
  (grepl("<tfoot", html, fixed = TRUE) %==% TRUE)
  # "nice" ticks for [0, 1] step at 0.2; end labels inset by the 4px pad, a
  # mid tick (0.4 -> x 32.8) is middle-anchored
  (grepl('<text x="4" y="15" text-anchor="start">0</text>', html, fixed = TRUE) %==% TRUE)
  (grepl('<text x="76" y="15" text-anchor="end">1</text>', html, fixed = TRUE) %==% TRUE)
  (grepl('<text x="32.8" y="15" text-anchor="middle">0.4</text>', html, fixed = TRUE) %==% TRUE)
  # the same ticks drive a stretched in-cell gridline background (one per row)
  (count_str(html, 'class="lt-eb-grid-bg"') %==% 2L)
  # the axis caption is centered below the ticks
  (grepl('class="lt-eb-axis-label" x="40" y="28" text-anchor="middle">Effect</text>',
    html, fixed = TRUE) %==% TRUE)

  # tick count adapts to width so labels do not crowd: a narrow axis keeps only
  # the endpoints, a wide one shows the full 0.2 step
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
  # one SVG for the single row, holding both series stacked at distinct y
  # (n = 2 at H = 28 -> rows at round(28/3) = 9 and round(56/3) = 19)
  (count_str(html, '<svg class="lt-eb"') %==% 1L)
  # each series takes its own color, as a fill= (point) / stroke= (bar) attr
  (grepl('<circle fill="#1b9e77" cx="40" cy="9"', html, fixed = TRUE) %==% TRUE)
  (grepl('<circle fill="#d95f02" cx="25.6" cy="19"', html, fixed = TRUE) %==% TRUE)
  (grepl('<line stroke="#1b9e77" x1="18.4" y1="9" x2="61.6" y2="9"', html, fixed = TRUE) %==% TRUE)
  (grepl('<line stroke="#d95f02" x1="11.2" y1="19" x2="40" y2="19"', html, fixed = TRUE) %==% TRUE)
  # the tooltip keys each series by its label
  (grepl('A: 0.5 (0.2, 0.8)', html, fixed = TRUE) %==% TRUE)
  # a single footer legend keyed by color + label (not one per row)
  (count_str(html, 'class="lt-plot-legend"') %==% 1L)
  (grepl('background:#1b9e77"></i>A</span>', html, fixed = TRUE) %==% TRUE)
  (grepl('background:#d95f02"></i>B</span>', html, fixed = TRUE) %==% TRUE)
})

assert("lt_dotplot stagger puts each column's dot on its own vertical track", {
  base = list(data = list(a = 1, b = 2, c = 3))
  op = list(type = "dotplot", columns = c("a", "b", "c"),
    min = 0, max = 4, width = 80, height = 40)
  # default: all three dots share the mid-line (cy = height/2 = 20)
  flat = build(c(base, list(ops = list(op))))
  (count_str(flat, 'cy="20"') %==% 3L)
  # stagger: evenly spaced tracks round((i+1)/(n+1)*H) -> 10, 20, 30
  staggered = build(c(base, list(ops = list(c(op, list(stagger = TRUE))))))
  (grepl('cy="10"', staggered, fixed = TRUE) %==% TRUE)
  (grepl('cy="30"', staggered, fixed = TRUE) %==% TRUE)
  (count_str(staggered, 'cy="20"') %==% 1L)
})

assert("lt_errorbar/lt_dotplot `into` draws into a runtime-synthesized column", {
  # `into` names a target column not in the data: an `add_col` op makes the
  # runtime materialize it, draw the plot into it, and leave the value columns
  # rendering as text. `fig` is that column.
  spec = list(
    data = list(est = c(0.5, 0.2), lo = c(0, 0.1), hi = c(1, 0.3)),
    ops = list(
      list(type = "add_col", column = "fig"),
      list(type = "errorbar", columns = I("est"), lowers = I("lo"),
        uppers = I("hi"), into = "fig", min = 0, max = 1, width = 80,
        height = 16))
  )
  html = build(spec)
  # the synthesized column carries a header and one SVG per row
  (grepl(">fig</th>", html, fixed = TRUE) %==% TRUE)
  (count_str(html, '<svg class="lt-eb"') %==% 2L)
  # the value column still renders its numbers as data cells (not consumed)
  (grepl(">0.5</td>", html, fixed = TRUE) %==% TRUE)
  (grepl(">0.2</td>", html, fixed = TRUE) %==% TRUE)
  # a dot plot into a (missing) dedicated column behaves the same
  dp = build(list(
    data = list(a = c(1, 2), b = c(3, 4)),
    ops = list(
      list(type = "add_col", column = "plot"),
      list(type = "dotplot", columns = c("a", "b"), into = "plot",
        min = 0, max = 4, width = 80, height = 16))
  ))
  (grepl(">plot</th>", dp, fixed = TRUE) %==% TRUE)
  (count_str(dp, '<svg class="lt-dot"') %==% 2L)
  (grepl(">1</td>", dp, fixed = TRUE) %==% TRUE)
  (grepl(">4</td>", dp, fixed = TRUE) %==% TRUE)
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
  (lti_eval(x, 't.querySelectorAll(".lt-plot-legend i").length') %==% '3')
  # monochrome by default: dots carry no fill override and no legend is drawn
  xm = lt(d) |> lt_dotplot(~ x + y + z)
  (lti_eval(xm, 't.querySelector("tbody .lt-dot circle").hasAttribute("fill")')
   %==% 'false')
  (lti_eval(xm, 't.querySelectorAll(".lt-plot-legend").length') %==% '0')
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
