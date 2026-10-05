# Typed, control-bar filters (lt_select / lt_range): a chip with a funnel popover
# holding a widget and an expression box, both editing one filter term (browser).

tdf = function() data.frame(name = sym, n = c(5, 12, 3, 8), grp = c('a', 'b', 'a', 'b'))

assert('lt_select filters by a column value and defaults to the first choice', {
  x = lt(tdf()) |> lt_interactive(filter = list(grp = lt_select()), pager = FALSE)
  # the default selects the first distinct value ("a"): only its rows show
  (lti_rows(x) %==% c('Rash', 'Headache'))
  # picking another value from the dropdown refilters
  pick = 'var s = t.querySelector(".lti-chip select"); s.value = "b"; s.onchange()'
  (lti_rows(x, pick) %==% c('Nausea', 'Itch'))
  # the expression box mirrors the pick, and the chip summary reads the label
  (lti_eval(x, 't.querySelector(".lti-chip input").value === String.raw`x == "b"`', pick)
   %==% 'true')
  (lti_eval(x, 't.querySelector(".lti-chip-cur").textContent', pick) %==% 'b')
})

assert('el._lt.view() reports the filtered rows a typed filter keeps', {
  # a download-what-is-shown button reads the current view; typed filters live in
  # state.filters (not external predicates), so view() must reflect them
  x = lt(tdf()) |> lt_interactive(filter = list(grp = lt_select()), pager = FALSE)
  # the default grp == "a" keeps rows 1 and 3 (every row, not just a page)
  (lti_eval(x, 't._lt.view().join(",")') %==% '1,3')
})

assert('lt_select can target a column hidden from the table', {
  x = lt(tdf()) |> lt_hide(~ grp) |>
    lt_interactive(filter = list(grp = lt_select(selected = 'b')), pager = FALSE)
  # grp is not a visible column, yet its filter still keeps only grp == "b" rows
  (lti_rows(x) %==% c('Nausea', 'Itch'))
})

assert('a typed-filter list can mix chips with plain per-column boxes', {
  # name gets a plain filter box; grp a dropdown chip -- both at once
  x = lt(tdf()) |> lt_interactive(
    filter = list(name = TRUE, grp = lt_select()), pager = FALSE)
  (lti_eval(x, 't.querySelectorAll(".lti-filters input").length') %==% '1')
  (lti_eval(x, 't.querySelectorAll(".lti-chip select").length') %==% '1')
  # the box filters its own column, composing with the chip's default (grp "a")
  box = 'var i = t.querySelectorAll(".lti-filters input")[0];
         i.value = "Rash"; i.dispatchEvent(new Event("change"))'
  (lti_rows(x, box) %==% c('Rash'))
})

assert('lt_range renders a two-thumb slider whose box filters numerically', {
  x = lt(tdf()) |> lt_interactive(filter = list(n = lt_range()), pager = FALSE)
  # a custom slider: exactly two <button> thumbs, no native range input
  (lti_eval(x, 't.querySelectorAll(".lti-thumb").length') %==% '2')
  (lti_eval(x, 't.querySelectorAll("input[type=range]").length') %==% '0')
  # no initial filter (full range): every row shows
  (length(lti_rows(x)) %==% 4L)
  # typing an expression in the box filters to n within [4, 9]
  box = 'var b = t.querySelector(".lti-chip input"); b.value = "x >= 4 && x <= 9"; b.onchange()'
  (lti_rows(x, box) %==% c('Rash', 'Itch'))
  # the box drives the thumbs: the low thumb moves off the left end
  (lti_eval(x, 'parseFloat(t.querySelectorAll(".lti-thumb")[0].style.left) > 0', box)
   %==% 'true')
})
