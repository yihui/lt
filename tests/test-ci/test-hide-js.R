# Interactive column-visibility menu (browser).

# whether header `ti` (0-based) and its first body cell are hidden
th_hidden = function(ti) sprintf('t.querySelectorAll("thead th")[%d].hidden', ti)
cell_hidden = function(ti) sprintf(
  't.querySelector("tbody tr").children[%d].hidden', ti)
# click column `ti`'s menu checkbox (toggles it)
box_click = function(ti) sprintf('t.querySelectorAll(".lti-menu input")[%d].click()', ti)

assert("the column menu lists every column and hides the unchecked ones", {
  x = itbl(hide = TRUE)
  # an icon button opens a checklist with one box per column, all checked
  (lti_eval(x, 't.querySelector(".lti-cols button") ? 1 : 0') %==% '1')
  (lti_eval(x, 't.querySelectorAll(".lti-menu input").length') %==% '2')
  (lti_eval(x, '[...t.querySelectorAll(".lti-menu input")].every(b => b.checked)')
   %==% 'true')
  # unchecking a box hides that column's header and cells; the other is untouched
  off1 = box_click(1)
  (lti_eval(x, th_hidden(1), off1) %==% 'true')
  (lti_eval(x, cell_hidden(1), off1) %==% 'true')
  (lti_eval(x, cell_hidden(0), off1) %==% 'false')
  # the hidden column stays hidden across a re-render (sorting the other column)
  sortN = 'document.querySelector("thead th .lti-label").click()'
  (lti_eval(x, cell_hidden(1), paste(off1, sortN, sep = ';')) %==% 'true')
  # re-checking restores it
  (lti_eval(x, th_hidden(1), paste(off1, box_click(1), sep = ';')) %==% 'false')
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
  # hiding body cells alone leaves a gap in a fixed layout; hide the <col> too
  x = itbl(hide = TRUE, resize = TRUE)
  off1 = box_click(1)
  (lti_eval(x, 't.querySelectorAll("col")[1].hidden', off1) %==% 'true')
  (lti_eval(x, th_hidden(1), off1) %==% 'true')
})

assert("hide accepts a formula, and the menu lists displayed labels", {
  # a formula selects which columns start hidden, same as a character vector
  x = itbl(hide = ~ n)
  (lti_eval(x, 't.querySelectorAll(".lti-menu input")[1].checked') %==% 'false')
  (lti_eval(x, th_hidden(1)) %==% 'true')
  # the checklist shows each column by its displayed label, not its raw name
  y = lt(data.frame(name = sym, n = c(5, 12, 3, 8))) |>
    lt_label(n = "Count") |> lt_interactive(hide = TRUE)
  labels = '[...t.querySelectorAll(".lti-menu label")].map(l => l.textContent).join("|")'
  (lti_eval(y, labels) %==% 'name|Count')
})

assert("hiding a column also hides its filter-row and plot-axis-footer cells", {
  # a hidden column must vanish from EVERY per-column row (filter boxes, plot
  # axis footer too), or the axis shifts off its column
  x = lt(data.frame(name = sym, a = c(1, 2, 3, 4), b = c(2, 3, 4, 5))) |>
    lt_dotplot(~ a + b, axis = TRUE) |>
    lt_interactive(hide = TRUE, filter = TRUE, pager = FALSE)
  # the first column ("name") owns a cell in the filter row and the plot-axis
  # footer row; both start shown
  filt = 't.querySelector("tr.lti-filters").children[0].hidden'
  foot = 't.querySelector("tr.lt-plot-foot").children[0].hidden'
  (lti_eval(x, filt) %==% 'false')
  (lti_eval(x, foot) %==% 'false')
  # toggling it off hides those cells as well as the header/body
  off0 = box_click(0)
  (lti_eval(x, filt, off0) %==% 'true')
  (lti_eval(x, foot, off0) %==% 'true')
  (lti_eval(x, cell_hidden(0), off0) %==% 'true')
  # and it stays hidden across a re-render (sorting another column)
  sortA = 'document.querySelectorAll("thead th .lti-label")[1].click()'
  (lti_eval(x, foot, paste(off0, sortA, sep = ';')) %==% 'true')
})

assert("hiding a column keeps the spanner row aligned with the body", {
  # spanner row merges cells, so column i is not at cell i; hide loop must
  # shrink the covering colSpan (drop it when empty), or spanners drift
  d = data.frame(a = 1:3, b = 4:6, c = 7:9, e = 10:12)
  x = lt(d) |> lt_spanner("G1", ~ a + b) |> lt_spanner("G2", ~ c + e) |>
    lt_interactive(hide = ~ a, pager = FALSE)
  g1 = 't.querySelector(".lt-spanner-row").children[0]'
  # a starts hidden: G1 (over a + b) shrinks from 2 to 1 but still shows (b left)
  (lti_eval(x, paste0(g1, ".colSpan")) %==% '1')
  (lti_eval(x, paste0(g1, ".hidden")) %==% 'false')
  # hiding b too empties G1, so it hides; G2 is untouched
  offb = box_click(1)
  (lti_eval(x, paste0(g1, ".hidden"), offb) %==% 'true')
  (lti_eval(x, 't.querySelector(".lt-spanner-row").children[1].colSpan', offb) %==% '2')
  # re-showing both restores G1's full span (idempotent across toggles)
  back = paste(offb, box_click(1), box_click(0), sep = ';')
  (lti_eval(x, paste0(g1, ".colSpan"), back) %==% '2')
  (lti_eval(x, paste0(g1, ".hidden"), back) %==% 'false')
})

assert("the menu groups columns under their spanners, indenting the children", {
  # spanner columns are listed under an indented group header, so repeated
  # labels (auto-span makes both Sepal.Length and Petal.Length "Length") stay
  # unambiguous
  x = lt(iris) |> lt_spanner() |> lt_interactive(hide = TRUE)
  rows = paste0(
    '[...t.querySelector(".lti-menu").children].map(e => ',
    'e.className + ":" + e.textContent.trim()).join("|")')
  (lti_eval(x, rows) %==% paste(
    'lti-group:Sepal', 'lti-sub:Length', 'lti-sub:Width',
    'lti-group:Petal', 'lti-sub:Length', 'lti-sub:Width',
    ':Species', sep = '|'))
  # the boxes stay in column order, so hiding box 0 hides the first data column
  off0 = box_click(0)
  (lti_eval(x, cell_hidden(0), off0) %==% 'true')
})

assert("hiding a column leaves an open detail row's full-width cell alone", {
  # hide loop keys cells by column index; a detail row's single spanning cell
  # must be skipped, not taken for column 0's
  x = itbl(hide = TRUE, detail = ~ n, pager = FALSE)
  expand = 't.querySelector(".lti-expand").click()'
  off0 = paste(expand, box_click(0), sep = ';')
  (lti_eval(x, 't.querySelector("tr.lti-detail td").hidden', off0) %==% 'false')
  (lti_eval(x, 't.querySelector("tr.lti-detail td").colSpan', off0) %==% '2')
  # the real first-column cell is still hidden, as asked
  (lti_eval(x, cell_hidden(0), off0) %==% 'true')
})

assert("hide = list(label=) shows a labeled chip in the bar instead of the eye", {
  x = itbl(hide = list(label = 'Show/Hide columns', columns = 'n'))
  (lti_eval(x, 't.querySelectorAll(".lti-cols > button").length') %==% '0')
  (lti_eval(x, 't.querySelector(".lti-cols .lti-chip-name").textContent')
   %==% 'Show/Hide columns')
  # the chip sits with the icons, after the filter chips, and opens the same checklist
  (lti_eval(x, 't.querySelectorAll(".lti-bar .lti-icons .lti-cols .lti-chip").length')
   %==% '1')
  open = 't.querySelector(".lti-chip").click()'
  (lti_eval(x, 't.querySelector(".lti-menu").hidden', open) %==% 'false')
  (lti_eval(x, th_hidden(1)) %==% 'true')
})

assert("the control bar orders search, chips, then icons", {
  x = itbl(hide = TRUE, download = TRUE, search = TRUE)
  (lti_eval(x, '[...t.querySelector(".lti-bar").children].map(e => e.className.split(" ")[0]).join()')
   %==% 'lti-search,lti-chips,lti-icons')
})
