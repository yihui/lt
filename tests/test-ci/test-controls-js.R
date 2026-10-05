# Interactive control wiring (browser): enabling/disabling sort and search,
# control rows spanning the table, and tables rendered on demand.

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
  sort2 = paste(make,
    't2.querySelectorAll("thead th")[1].querySelector(".lti-label").click()', sep = ';')
  (lti_eval(x, rows, sort2) %==% 'Headache|Rash')
  (lti_eval(
    x, '[...t.querySelectorAll("tbody tr")].map(r => r.children[0].textContent).join("|")',
    sort2
  ) %==% 'Rash|Nausea')
})
