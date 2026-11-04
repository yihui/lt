# Date and date-time columns (browser): a default display format, chronological
# sort, text filter expressions, and a range slider; plus column type tags in
# the filter row, which is made of <th> cells.

dfl = function(...) lt(data.frame(
  name = c('c', 'a', 'b'),
  when = as.Date(c('2024-03-05', '2023-12-25', '2024-01-10')),
  at = as.POSIXct(c('2024-03-05 10:30:00', '2023-12-25 08:00:00', '2024-01-10 23:59:59'), tz = 'UTC')
), ...)

assert('dates and date-times get a default format that lt_date() overrides', {
  x = dfl() |> lt_interactive(pager = FALSE)
  (lti_col(x, 1) %==% c('2024-03-05', '2023-12-25', '2024-01-10'))
  # date-times show in the local time zone (the instant is shipped as UTC)
  (lti_col(x, 2) %==% format(dfl()$data$at, '%Y-%m-%d %H:%M:%S', tz = ''))
  (lti_col(dfl(auto_format = FALSE) |> lt_interactive(pager = FALSE), 1) != '2024-03-05')
  (lti_col(dfl() |> lt_date(~ when, method = 'toISOString') |> lt_interactive(pager = FALSE), 1)
   %==% c('2024-03-05T00:00:00.000Z', '2023-12-25T00:00:00.000Z', '2024-01-10T00:00:00.000Z'))
})

assert('a date column sorts by time and filters by text expressions', {
  x = dfl() |> lt_interactive(pager = FALSE)
  click = 'document.querySelectorAll("thead th .lti-label")[1].click()'
  (lti_rows(x, click) %==% c('a', 'b', 'c'))
  (lti_rows(x, paste(click, click, sep = ';')) %==% c('c', 'b', 'a'))
  x = dfl() |> lt_interactive(filter = list(when = 'auto'), pager = FALSE)
  box = 'var b = t.querySelector(".lti-filters .lti-pop input");
         b.value = "x >= \\"2024-01-01\\""; b.onchange()'
  (lti_rows(x, box) %==% c('c', 'b'))
  # the range slider reads out dates
  (lti_eval(x, 't.querySelector(".lti-slider-out").textContent', box) %==% '2023-12-25 – 2024-03-05')
})

assert('show_types puts type tags under the labels, beside any filter control', {
  tags = '[...t.querySelectorAll("thead tr:nth-child(2) .lt-type")].map(e => e.textContent).join("")'
  # static table: a tag row below the label row, whose cells are all <th>
  x = dfl(show_types = TRUE)
  (lti_eval(x, tags) %==% '<chr><date><time>')
  (lti_eval(x, 't.querySelectorAll("thead td").length') %==% '0')
  # interactive: the tag row doubles as the filter row, tag and funnel in one cell
  x = dfl(show_types = TRUE) |> lt_interactive(pager = FALSE)
  (lti_eval(x, '[...t.querySelectorAll(".lti-filters .lt-type")].map(e => e.textContent).join("")')
   %==% '<chr><date><time>')
  (lti_eval(x, 't.querySelectorAll(".lti-filters").length') %==% '1')
  (lti_eval(x, 't.querySelectorAll(".lti-filters th")[1].querySelectorAll(".lt-type, .lti-funnel").length') %==% '2')

  # without the flag, no tags
  (lti_eval(dfl() |> lt_interactive(), 't.querySelectorAll(".lt-type").length') %==% '0')
})

assert('the filter row uses <th> cells, so it closes the header', {
  x = dfl() |> lt_interactive()
  (lti_eval(x, 't.querySelectorAll(".lti-filters td").length') %==% '0')
  (lti_eval(x, 'getComputedStyle(t.querySelector(".lti-filters th")).borderBottomStyle') %==% 'solid')
})
