# Typed column filters: a funnel + popover (holding a widget and an expression
# box, both editing one filter term) under a visible column's header, or as a
# control-bar chip for a hidden column (browser).

tdf = function() data.frame(name = sym, n = c(5, 12, 3, 8), grp = c('a', 'b', 'a', 'b'))

assert('a "select" on a visible column is a header funnel that defaults to no filter', {
  x = lt(tdf()) |> lt_interactive(filter = list(grp = 'select'), pager = FALSE)
  # a visible column's control sits under its header (the filter row), not in a chip
  (lti_eval(x, 't.querySelectorAll(".lti-filters .lti-funnel").length') %==% '1')
  (lti_eval(x, 't.querySelectorAll(".lti-chip").length') %==% '0')
  # no value is pre-selected, so a bare "select" shows every row on load (a seeded
  # first-choice filter would silently hide rows the reader never asked to hide)
  (length(lti_rows(x)) %==% 4L)
  # the dropdown offers a leading blank "no filter" choice before the distinct values
  (lti_eval(x, 'Array.from(t.querySelectorAll(".lti-filters select option")).map(o => o.value).join(",")')
   %==% ',a,b')
  # picking a value from the dropdown filters to it
  pick = 'var s = t.querySelector(".lti-filters select"); s.value = "b"; s.onchange()'
  (lti_rows(x, pick) %==% c('Nausea', 'Itch'))
  # the expression box mirrors the pick
  (lti_eval(x, 't.querySelector(".lti-filters .lti-pop input").value === String.raw`x == "b"`', pick)
   %==% 'true')
  # choosing the blank clears the filter: every row again
  clear = 'var s = t.querySelector(".lti-filters select"); s.value = "b"; s.onchange();
           s.value = ""; s.onchange()'
  (length(lti_rows(x, clear)) %==% 4L)
})

assert('a "select" with a `selected` value seeds that filter on load', {
  x = lt(tdf()) |> lt_interactive(
    filter = list(grp = list(type = 'select', selected = 'b')), pager = FALSE)
  (lti_rows(x) %==% c('Nausea', 'Itch'))
})

assert('el._lt.view() reports the rows a typed filter keeps', {
  # a download-what-is-shown button reads the current view; typed filters live in
  # state.filters (not external predicates), so view() must reflect them
  x = lt(tdf()) |> lt_interactive(
    filter = list(grp = list(type = 'select', selected = 'a')), pager = FALSE)
  # grp == "a" keeps rows 1 and 3 (every row, not just a page)
  (lti_eval(x, 't._lt.view().join(",")') %==% '1,3')
})

assert('a typed filter on a hidden column becomes a labelled control-bar chip', {
  x = lt(tdf()) |> lt_hide(~ grp) |> lt_interactive(
    filter = list(grp = list(type = 'select', selected = 'b', label = 'Group')),
    pager = FALSE)
  # grp is not a visible column: it renders as a chip in the head bar, carrying
  # its label and a summary of the current value
  (lti_eval(x, 't.querySelector(".lti-chip-name").textContent') %==% 'Group')
  (lti_eval(x, 't.querySelector(".lti-chip-cur").textContent') %==% 'b')
  # and the hidden column's filter still keeps only grp == "b" rows
  (lti_rows(x) %==% c('Nausea', 'Itch'))
})

assert('an unnamed default entry boxes the other columns alongside a typed column', {
  # grp gets a dropdown funnel; every other visible column (name, n) a plain box
  x = lt(tdf()) |> lt_interactive(filter = list(TRUE, grp = 'select'), pager = FALSE)
  (lti_eval(x, 't.querySelectorAll(".lti-filters > td > .lti-search").length') %==% '2')
  (lti_eval(x, 't.querySelectorAll(".lti-filters select").length') %==% '1')
  # the box filters its own column (the dropdown adds no default filter of its own)
  box = 'var i = t.querySelector(".lti-filters > td > .lti-search");
         i.value = "Rash"; i.dispatchEvent(new Event("change"))'
  (lti_rows(x, box) %==% c('Rash'))
})

assert('a "range" filter renders a two-thumb slider whose box filters numerically', {
  x = lt(tdf()) |> lt_interactive(filter = list(n = 'range'), pager = FALSE)
  # a custom slider: exactly two <button> thumbs, no native range input
  (lti_eval(x, 't.querySelectorAll(".lti-thumb").length') %==% '2')
  (lti_eval(x, 't.querySelectorAll("input[type=range]").length') %==% '0')
  # no initial filter (full range): every row shows
  (length(lti_rows(x)) %==% 4L)
  # typing an expression in the box filters to n within [4, 9]
  box = 'var b = t.querySelector(".lti-filters .lti-pop input"); b.value = "x >= 4 && x <= 9"; b.onchange()'
  (lti_rows(x, box) %==% c('Rash', 'Itch'))
  # the box drives the thumbs: the low thumb moves off the left end
  (lti_eval(x, 'parseFloat(t.querySelectorAll(".lti-thumb")[0].style.left) > 0', box)
   %==% 'true')
})

assert('a chip value summary updates only once its popover closes, not while editing', {
  # the chip text is variable width; updating it live while dragging would shift
  # the funnel (and popover) sideways, so it is deferred until the popover closes
  x = lt(tdf()) |> lt_hide(~ n) |> lt_interactive(filter = list(n = 'range'), pager = FALSE)
  js = 'var f = t.querySelector(".lti-chip .lti-funnel"); f.click();
        var b = t.querySelector(".lti-chip .lti-pop input");
        b.value = "x >= 6 && x <= 10"; b.onchange();
        var during = t.querySelector(".lti-chip-cur").textContent;
        t.ownerDocument.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
        var after = t.querySelector(".lti-chip-cur").textContent'
  # empty while the popover is open, filled in only after it closes
  (lti_eval(x, 'during + "|" + after', js) %==% '|6 – 10')
})

assert('a popover flips to the funnel right against the scroll box, not the viewport', {
  x = lt(tdf()) |> lt_interactive(filter = list(grp = 'select'), search = FALSE, pager = FALSE)
  # a narrow scroll box with room to spare in the viewport: a panel that would
  # overflow the box must still flip (anchored right:0), gauged by the box edge
  narrow = 'var w = t.closest(".lt-wrap"); w.style.width = "150px"; w.style.overflowX = "auto";
            t.querySelector(".lti-funnel").click()'
  (lti_eval(x, 't.querySelector(".lti-pop-panel").style.right === "0px"', narrow) %==% 'true')
  # a wide box leaves the panel at its default left anchor (no inline right)
  wide = 'var w = t.closest(".lt-wrap"); w.style.width = "1200px";
          t.querySelector(".lti-funnel").click()'
  (lti_eval(x, 't.querySelector(".lti-pop-panel").style.right === ""', wide) %==% 'true')
})
