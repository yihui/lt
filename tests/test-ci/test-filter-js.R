# Interactive per-column filter boxes (browser).

assert("a column filter box filters on its own column", {
  x = itbl(filter = TRUE)
  set = function(i, term) sprintf(
    'var i = t.querySelectorAll("thead th input")[%d];
     i.value = %s; i.dispatchEvent(new Event("change"))', i, xfun::tojson(term)
  )
  (lti_rows(x, set(0, 'a')) %==% c("Rash", "Nausea", "Headache"))
  (lti_rows(x, set(1, 'x > 5')) %==% c("Nausea", "Itch"))
  # a character vector picks the columns that get a box
  (lti_eval(itbl(filter = 'n'), 't.querySelectorAll("thead th input").length') %==% '1')
  # on by default (auto); FALSE turns it off, and the filters live in <thead>,
  # so they survive a re-render of <tbody>
  (lti_eval(itbl(filter = FALSE), 't.querySelectorAll("thead th input, thead th .lti-funnel").length') %==% '0')
  (lti_eval(x, 't.querySelectorAll("thead th input").length', set(0, 'a')) %==% '2')
})
