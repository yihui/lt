# Interactive column resizing (browser).

# Widths of header cells with resize grip, table width, and drag of grip
# `i` by `dx` px (pointer events of real drag: down on grip, then move/up
# anywhere).
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
  # one grip per column in header cells, one <col> per width
  (lti_eval(x, 't.querySelectorAll("thead th .lti-resizer").length') %==% '2')
  (lti_eval(x, 't.querySelectorAll("colgroup col").length') %==% '2')
  # first column grows by drag distance; second untouched, so table
  # grows as much and wrapper can scroll to it
  probe = '[w(0) - w0, w(1) - w1, tw() - t0].map(Math.round).join(",")'
  (lti_eval(x, probe, paste(MEASURE, drag(0, 40))) %==% '40,0,40')
  (lti_eval(x, 't.className', drag(0, 40)) %==% 'lt-table lti-fixed')
  # widths live outside <tbody>, so sorting (re-renders it) keeps them
  (lti_eval(x, probe,
    paste(MEASURE, drag(0, 40), 'th(1).querySelector(".lti-label").click()'))
    %==% '40,0,40')
})

assert("a column shrinks to the minimum width, and a double-click fits it again", {
  x = itbl(resize = TRUE)
  # dragging far left shrinks column to MIN_COL (24px); content clipped
  # (cell is overflow:hidden once fixed), not spilling into next column or
  # under grip
  (lti_eval(x, 'Math.round(w(0))', paste(MEASURE, drag(0, -1000))) %==% '24')
  (lti_eval(x, 'getComputedStyle(th(0)).overflow', paste(MEASURE, drag(0, -1000)))
    %==% 'hidden')
  # double-click on grip restores column's content width
  fit = paste(MEASURE, drag(0, -1000),
              't.querySelector(".lti-resizer").dispatchEvent(
                 new MouseEvent("dblclick", {bubbles: true}))')
  (lti_eval(x, 'Math.round(w(0) - w0)', fit) %==% '0')
})

assert("the click that follows a resize drag does not sort the column", {
  x = itbl(resize = TRUE, sort = TRUE)
  # clicking label sorts column (ascending); sort binds to label, not whole cell
  sorted = 'th(0).getAttribute("aria-sort")'
  (lti_eval(x, sorted, paste(MEASURE, 'th(0).querySelector(".lti-label").click()'))
    %==% 'ascending')
  # dragging grip past column min width leaves pointer off grip, so browser
  # fires trailing click on <th> (not label); that click must not sort
  after = paste(MEASURE, drag(0, -1000),
    'th(0).dispatchEvent(new MouseEvent("click", {bubbles: true}))')
  (lti_eval(x, sorted, after) %==% 'null')
})

assert("a preset column width (lt_width) does not block shrinking by drag", {
  # width set by lt_width() is a starting width, not floor: grip still drags
  # column down to MIN_COL (24px). Checked with sort off and on, since sort
  # wraps the label (earlier floor measured it)
  d = data.frame(name = sym, n = c(5, 12, 3, 8))
  shrunk = function(s) {  # first column width after dragging grip far left
    x = lt(d) |> lt_width(name = '200px') |> lt_interactive(resize = TRUE, sort = s)
    lti_eval(x, 'Math.round(w(0))', paste(MEASURE, drag(0, -500)))
  }
  (shrunk(FALSE) %==% '24')
  (shrunk(TRUE) %==% '24')
})

assert("resizing is off by default", {
  (lti_eval(itbl(), 't.querySelectorAll(".lti-resizer").length') %==% '0')
  (lti_eval(itbl(), 't.className') %==% 'lt-table')
})
