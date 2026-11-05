# Date and date-time columns (browser): a default display format, chronological
# sort, text filter expressions, and a range slider; plus column type tags in
# the header cells.

dfl = function(...) lt(data.frame(
  name = c('c', 'a', 'b'),
  when = as.Date(c('2024-03-05', '2023-12-25', '2024-01-10')),
  at = as.POSIXct(c('2024-03-05 10:30:00', '2023-12-25 08:00:00', '2024-01-10 23:59:59'), tz = 'UTC')
), ...)

# TODO: date serialization (plain strings; UTC instants) needs xfun >= 0.62.11
if (xfun::pkg_available('xfun', '0.62.11')) {
assert('dates and date-times get a default format that lt_date() overrides', {
  x = dfl() |> lt_interactive(pager = FALSE)
  (lti_col(x, 1) %==% c('2024-03-05', '2023-12-25', '2024-01-10'))
  # date-times show in the local time zone (the instant is shipped as UTC)
  (lti_col(x, 2) %==% format(dfl()$data$at, '%Y-%m-%d %H:%M:%S', tz = ''))
  (lti_col(dfl(auto_format = FALSE) |> lt_interactive(pager = FALSE), 1) != '2024-03-05')
  # a calendar day shows as itself in any time zone
  (lti_col(dfl() |> lt_date(~ when, locale = 'en-US', options = list(month = 'short', day = 'numeric', year = 'numeric'))
     |> lt_interactive(pager = FALSE), 1) %==% c('Mar 5, 2024', 'Dec 25, 2023', 'Jan 10, 2024'))
})

assert('a date-time column at UTC midnights still shows its time', {
  x = lt(data.frame(t = as.POSIXct('2024-03-05', tz = 'UTC'))) |> lt_interactive(pager = FALSE)
  (nchar(lti_col(x, 0)) %==% 19L)
})

assert('a date column sorts by time and filters by text expressions', {
  x = dfl() |> lt_interactive(pager = FALSE)
  click = 'document.querySelectorAll("thead th .lti-label")[1].click()'
  (lti_rows(x, click) %==% c('a', 'b', 'c'))
  (lti_rows(x, paste(click, click, sep = ';')) %==% c('c', 'b', 'a'))
  x = dfl() |> lt_interactive(filter = list(when = 'auto'), pager = FALSE)
  box = 'var b = t.querySelector("thead th .lti-pop input");
         b.value = "x >= \\"2024-01-01\\""; b.onchange()'
  (lti_rows(x, box) %==% c('c', 'b'))
  # the range slider reads out dates
  (lti_eval(x, 't.querySelector(".lti-slider-out").textContent', box) %==% '2023-12-25 – 2024-03-05')
})
}

assert('show_types puts type tags under the labels, beside any filter control', {
  tags = '[...t.querySelectorAll("thead th .lt-type")].map(e => e.textContent).join("")'
  # static table: the tag sits in the label cell, after a line break
  x = dfl(show_types = TRUE)
  (lti_eval(x, tags) %==% '<chr><date><time>')
  (lti_eval(x, 't.querySelectorAll("thead tr").length') %==% '1')
  # interactive: label, sort mark, a break, the tag, a break, and the funnel
  x = dfl(show_types = TRUE) |> lt_interactive(pager = FALSE)
  (lti_eval(x, tags) %==% '<chr><date><time>')
  (lti_eval(x, '[...t.querySelectorAll("thead th")][1].children.length') %==% '7')  # + the resize grip
  (lti_eval(x, '[...t.querySelectorAll("thead th")][1].className') %==% 'lti-sortable')
  (lti_eval(x, '[...t.querySelectorAll("thead th")][1].querySelector(".lti-label + .lti-sort + br + .lt-type + br + .lti-pop") != null') %==% 'true')
  # labels stay clean for the column menu and CSV
  (lti_eval(dfl(show_types = TRUE) |> lt_interactive(hide = TRUE), 'document.querySelector(".lti-cols").textContent') != '')
  # without the flag, no tags
  (lti_eval(dfl() |> lt_interactive(), 't.querySelectorAll(".lt-type").length') %==% '0')
})
