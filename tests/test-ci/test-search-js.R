# Interactive global search box (browser).

assert("the search box filters the rendered rows", {
  x = itbl()
  # `change` event (Enter, or leaving box) applies term immediately,
  # bypassing debounce of `input` events
  find = function(term) sprintf(
    'var i = t.querySelector(".lti-search");
     i.value = %s; i.dispatchEvent(new Event("change"))', xfun::tojson(term)
  )
  (lti_rows(x, find('rash')) %==% 'Rash')
  (lti_rows(x, find('!rash')) %==% c("Nausea", "Headache", "Itch"))
  (lti_rows(x, find('x > 5')) %==% c("Nausea", "Itch"))
  # no matches: single placeholder row spanning table
  (lti_eval(x, 't.querySelectorAll("tbody .lti-empty td").length', find('zzz')) %==% '1')
  (lti_eval(x, 't.querySelector("tbody td").colSpan', find('zzz')) %==% '2')
})
