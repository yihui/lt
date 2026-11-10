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
  (lti_rows(x, find('does not contain rash')) %==% c("Nausea", "Headache", "Itch"))
  (lti_rows(x, find('name excludes ra')) %==% c("Nausea", "Headache", "Itch"))
  (lti_rows(x, find('x > 5')) %==% c("Nausea", "Itch"))
  # no matches: single placeholder row spanning table
  (lti_eval(x, 't.querySelectorAll("tbody .lti-empty td").length', find('zzz')) %==% '1')
  (lti_eval(x, 't.querySelector("tbody td").colSpan', find('zzz')) %==% '2')
  # plain language: conditions on columns, read without changing the typed text
  (lti_rows(x, find('n over 10')) %==% 'Nausea')
  (lti_eval(x, 't.querySelector(".lti-nl").textContent', find('n over 10')) %==% 'n: x > 10')
  (lti_eval(x, 't.querySelector(".lti-search").value', find('n over 10')) %==% 'n over 10')
  (lti_eval(x, 't.querySelector(".lti-nl").textContent', find('rash')) %==% '')
  # `,` / `;` join conditions, `or` alternates, bare words must all match
  (lti_rows(x, find('n over 4, name has a')) %==% c("Rash", "Nausea"))
  (lti_rows(x, find('n under 4 or n over 10')) %==% c("Nausea", "Headache"))
  (lti_rows(x, find('name is rash or name is itch')) %==% c("Rash", "Itch"))
  (lti_rows(x, find('ea ch')) %==% 'Headache')
})

assert("a column label with spaces can be named in the query", {
  d = data.frame(Sepal_Length = c(5, 7, 6), Species = c('a', 'b', 'a'))
  x = lt(d, labels = c(Sepal_Length = 'Sepal Length')) |> lt_interactive()
  find = function(term) sprintf(
    'var i = t.querySelector(".lti-search");
     i.value = %s; i.dispatchEvent(new Event("change"))', xfun::tojson(term)
  )
  (lti_rows(x, find('sepal length over 5.5')) %==% c('7', '6'))
  # the original column name still works alongside the label
  (lti_rows(x, find('Sepal_Length over 5.5')) %==% c('7', '6'))
})

assert("search boxes drop down random example queries", {
  # examples are random per page load, so read them from one page
  opts = function(sel) sprintf('Array.from(t.querySelector("%s").list.options, o => o.value).join("|")', sel)
  x = itbl()
  parts = strsplit(lti_eval(x, opts('.lti-search')), '|', fixed = TRUE)[[1]]
  # the first two are numeric and text, in that order
  (grepl('^"n" ', parts[1]))
  (grepl('^"name" ', parts[2]))
  # the placeholder shows a sample
  (lti_eval(x, 't.querySelector(".lti-search").placeholder.startsWith(\'e.g. "n" \')') %==% 'true')
  # picking one (an input event with no typing) applies it at once, no debounce
  pick = 'var i = t.querySelector(".lti-search"); i.value = i.list.options[0].value;
          i.dispatchEvent(new Event("input"))'
  (lti_eval(x, 't.querySelector(".lti-nl").textContent !== ""', pick) %==% 'true')
  # each column's own box gets examples without a column name
  y = itbl(filter = TRUE)
  col = strsplit(lti_eval(y, opts('thead th input')), '|', fixed = TRUE)[[1]]
  (length(col) > 0L)
  (!any(grepl('^n(ame)? ', col)))
  # search = FALSE: no box, so no examples
  (lti_eval(itbl(search = FALSE, filter = FALSE), 't.querySelectorAll("datalist").length') %==% '0')
})
