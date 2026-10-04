# Interactive per-column filter boxes (browser).

assert("a column filter box filters on its own column", {
  x = itbl(filter = TRUE)
  set = function(i, term) sprintf(
    'var i = t.querySelectorAll(".lti-filters input")[%d];
     i.value = %s; i.dispatchEvent(new Event("change"))', i, xfun::tojson(term)
  )
  (lti_rows(x, set(0, 'a')) %==% c("Rash", "Nausea", "Headache"))
  (lti_rows(x, set(1, 'x > 5')) %==% c("Nausea", "Itch"))
  # a character vector picks the columns that get a box
  (lti_eval(itbl(filter = 'n'), 't.querySelectorAll(".lti-filters input").length') %==% '1')
  # off by default, and the filter row lives in <thead>, so it survives a
  # re-render of <tbody>
  (lti_eval(itbl(), 't.querySelectorAll(".lti-filters").length') %==% '0')
  (lti_eval(x, 't.querySelectorAll("thead .lti-filters input").length', set(0, 'a')) %==% '2')
})
