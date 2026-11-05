# Column profile (browser): a histogram or top-value bars in each header, with
# summary stats as the tooltip.

prof = function(x, i) strsplit(lti_eval(
  x, sprintf('[...t.querySelectorAll(".lti-prof")].map(p => p.title + "#" + p.querySelectorAll("rect:not(.s)").length)[%d]', i)
), '#', fixed = TRUE)[[1]]

assert('profile draws a histogram for numbers and top-value bars for text', {
  x = lt(data.frame(n = c(1, 2, 3, 6, NA, 1, 2, 3), s = c('a', 'b', 'a', 'a', 'c', 'a', 'b', 'a'))) |>
    lt_interactive(profile = TRUE, filter = FALSE)
  p = prof(x, 0)
  (p %==% c('min 1; max 6; mean 2.571; 13% NA', '4'))
  (prof(x, 1) %==% c('a (5), b (2), c (1)', '3'))
})

assert('profile is off by default, and covers dates', {
  d = lt(data.frame(n = 1:3))
  (lti_eval(d |> lt_interactive(), 'document.querySelectorAll(".lti-prof").length') %==% '0')
  if (xfun::pkg_available('xfun', '0.62.11')) {
    x = lt(data.frame(d = as.Date(c('2024-01-01', '2024-03-01')))) |> lt_interactive(profile = TRUE)
    (prof(x, 0)[1] %==% 'min 2024-01-01; max 2024-03-01')
  }
})

assert('profile has no gaps or false rounding for few distinct values, and truncates top values', {
  x = lt(data.frame(y = rep(2007:2009, 6), s = rep(letters[1:9], 2))) |>
    lt_interactive(profile = TRUE, filter = FALSE)
  (prof(x, 0) %==% c('min 2007; max 2009; mean 2008', '3'))
  (grepl('^9 distinct; top ', prof(x, 1)[1]))
  (prof(x, 1)[2] %==% '9')
  # too many categories, or all NA: an empty svg as placeholder
  y = lt(data.frame(s = as.character(1:10), z = NA_real_)) |> lt_interactive(profile = TRUE, filter = FALSE)
  (lti_eval(y, '[...document.querySelectorAll(".lti-prof")].map(p => p.querySelectorAll("svg").length + ":" + p.querySelectorAll("rect").length)') %==% '1:0,1:0')
})

assert('profile = "filter" moves the profile into the popover', {
  x = lt(data.frame(n = c(1, 5, 9))) |> lt_interactive(profile = 'filter')
  (lti_eval(x, 'document.querySelectorAll("th > .lti-prof").length + "," + document.querySelectorAll(".lti-prof").length') %==% '0,1')
})

assert('profile bars highlight the rows kept by the filters', {
  x = lt(data.frame(y = rep(2007:2009, 3))) |> lt_interactive(profile = TRUE, filter = FALSE)
  h = 'Array.from(t.querySelectorAll("rect.s"), r => (+r.getAttribute("height")).toFixed(2)).join(",")'
  (lti_eval(x, h) %==% '')  # no filter, no overlay
  (lti_eval(x, h, 't._lt.filter("a", r => r.y == 2008)') %==% '0.00,1.00,0.00')
})

assert('categorical profile counts NA as a value', {
  x = lt(data.frame(s = c('a', 'a', 'b', NA, 'a'))) |> lt_interactive(profile = TRUE, filter = FALSE)
  (prof(x, 0)[1] %==% 'a (3), b (1); 1 NA')
})
