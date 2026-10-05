# Interactive column resizing (browser).

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
  (lti_eval(x, probe,
    paste(MEASURE, drag(0, 40), 'th(1).querySelector(".lti-label").click()'))
    %==% '40,0,40')
})

assert("a column cannot be dragged away, and a double-click fits it again", {
  x = itbl(resize = TRUE)
  # dragging far to the left stops before the grip reaches the header label: the
  # resizer's left edge stays at or past the right edge of the label + indicator
  past = 'var g = t.querySelectorAll(".lti-resizer")[0];
    var ind = g.parentNode.querySelector(".lti-sort");
    (g.getBoundingClientRect().left >= Math.floor(ind.getBoundingClientRect().right))'
  (lti_eval(x, past, drag(0, -1000)) %==% 'true')
  # a double-click on the grip restores the column's content width
  fit = paste(MEASURE, drag(0, -1000),
              't.querySelector(".lti-resizer").dispatchEvent(
                 new MouseEvent("dblclick", {bubbles: true}))')
  (lti_eval(x, 'Math.round(w(0) - w0)', fit) %==% '0')
})

assert("the click that follows a resize drag does not sort the column", {
  x = itbl(resize = TRUE, sort = TRUE)
  # clicking the label sorts the column (ascending); the sort binds to the label,
  # not the whole cell
  sorted = 'th(0).getAttribute("aria-sort")'
  (lti_eval(x, sorted, paste(MEASURE, 'th(0).querySelector(".lti-label").click()'))
    %==% 'ascending')
  # dragging the grip past the column min width leaves the pointer off the grip,
  # so the browser fires the trailing click on the <th> (not the label); that
  # click must not sort
  after = paste(MEASURE, drag(0, -1000),
    'th(0).dispatchEvent(new MouseEvent("click", {bubbles: true}))')
  (lti_eval(x, sorted, after) %==% 'null')
})

assert("resizing is off by default", {
  (lti_eval(itbl(), 't.querySelectorAll(".lti-resizer").length') %==% '0')
  (lti_eval(itbl(), 't.className') %==% 'lt-table')
})
