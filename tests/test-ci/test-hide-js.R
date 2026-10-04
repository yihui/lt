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
  sortN = 'document.querySelectorAll("thead th")[0].click()'
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
  # the body cells alone would leave a gap in a fixed-layout table; the <col>
  # must be hidden too for the column to collapse
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

assert("hiding a column leaves an open detail row's full-width cell alone", {
  # the hide loop keys cells by column index, but a detail row has one cell
  # spanning every column; it must skip that cell, not take it for column 0's
  x = itbl(hide = TRUE, detail = ~ n, pager = FALSE)
  expand = 't.querySelector(".lti-expand").click()'
  off0 = paste(expand, box_click(0), sep = ';')
  (lti_eval(x, 't.querySelector("tr.lti-detail td").hidden', off0) %==% 'false')
  (lti_eval(x, 't.querySelector("tr.lti-detail td").colSpan', off0) %==% '2')
  # the real first-column cell is still hidden, as asked
  (lti_eval(x, cell_hidden(0), off0) %==% 'true')
})
