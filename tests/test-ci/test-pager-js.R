# Interactive pager (browser): page slicing, defaults, Inf page size, and the
# page-size selector.

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

assert("paging is on by default; the size selector drops when no size splits", {
  # default sizes, 4 rows: pager shows but no size splits, so no selector
  (lti_eval(itbl(), 'document.querySelector(".lti-pos").textContent') %==% '1–4 / 4')
  (lti_eval(itbl(), 'document.querySelectorAll(".lti-pager select").length') %==% '0')
  # a size below the row count brings the selector back
  (lti_eval(itbl(pager = c(2, 10)),
            'document.querySelectorAll(".lti-pager select").length') %==% '1')
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
  # a search dropped rows, so the full count trails in parens
  (lti_eval(x, 'document.querySelector(".lti-pos").textContent', find) %==% '1–2 / 3 (4)')
  none = 'var i = t.querySelector(".lti-search");
          i.value = "zzz"; i.dispatchEvent(new Event("change"))'
  (lti_eval(x, 'document.querySelector(".lti-pos").textContent', none) %==% '0 / 0 (4)')
})
