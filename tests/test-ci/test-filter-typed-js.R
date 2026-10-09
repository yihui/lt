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

assert('a chip opens its popover on a click anywhere, aligned to the chip left edge', {
  x = lt(tdf()) |> lt_hide(~ grp) |> lt_interactive(
    filter = list(grp = list(type = 'select', label = 'Group')), pager = FALSE)
  # clicking the label (not the funnel) toggles the popover: the whole chip is the
  # click target
  open = 't.querySelector(".lti-chip-name").click()'
  (lti_eval(x, '!t.querySelector(".lti-pop-panel").hidden', open) %==% 'true')
  # and the panel opens flush with the chip's left edge, not the funnel's
  align = paste(open,
    'var p = t.querySelector(".lti-pop-panel").getBoundingClientRect(),
         c = t.querySelector(".lti-chip").getBoundingClientRect()',
    sep = ';')
  (lti_eval(x, 'Math.abs(p.left - c.left) <= 2', align) %==% 'true')
  # a click inside the open panel leaves it open
  stay = paste(open, 't.querySelector(".lti-pop-panel").click()', sep = ';')
  (lti_eval(x, '!t.querySelector(".lti-pop-panel").hidden', stay) %==% 'true')
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

assert('a bare thumb click (pointer down + up, no move) does not re-filter', {
  # clicking a thumb without dragging leaves the range unchanged, so it must not
  # commit a filter and rebuild <tbody>. A fresh <tbody> would drop a stamp we
  # put on the current one, so its survival proves no re-render happened.
  x = lt(tdf()) |> lt_interactive(filter = list(n = 'range'), pager = FALSE)
  js = 't.querySelector(".lti-filters .lti-funnel").click();
    var th = t.querySelectorAll(".lti-thumb")[0], cx = th.getBoundingClientRect().left;
    var ev = (n, c) => new PointerEvent(n, {bubbles: true, cancelable: true, clientX: c});
    t.tBodies[0].dataset.probe = "1";
    th.dispatchEvent(ev("pointerdown", cx));
    document.dispatchEvent(ev("pointerup", cx))'
  (lti_eval(x, 't.tBodies[0].dataset.probe === "1"', js) %==% 'true')
})

assert('dragging a thumb to a new value commits the narrowed range on release', {
  # the positive path: an actual drag (down, move, up) must re-filter. Pulling the
  # low thumb to the track center raises the lower bound, dropping the small values.
  x = lt(tdf()) |> lt_interactive(filter = list(n = 'range'), pager = FALSE)
  js = 't.querySelector(".lti-filters .lti-funnel").click();
    var th = t.querySelectorAll(".lti-thumb")[0], r = th.closest(".lti-slider").getBoundingClientRect();
    var ev = (n, c) => new PointerEvent(n, {bubbles: true, cancelable: true, clientX: c});
    th.dispatchEvent(ev("pointerdown", r.left));
    document.dispatchEvent(ev("pointermove", r.left + r.width / 2));
    document.dispatchEvent(ev("pointerup", r.left + r.width / 2))'
  (length(lti_rows(x, js)) < 4L)
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

assert('a "checklist" keeps the checked values (every box checked = no filter)', {
  x = lt(tdf()) |> lt_interactive(filter = list(grp = 'checklist'), pager = FALSE)
  # a visible column's checklist sits under its header, one checkbox per value
  (lti_eval(x, 't.querySelectorAll(".lti-filters .lti-funnel").length') %==% '1')
  (lti_eval(x, 't.querySelectorAll(".lti-filters .lti-check input").length') %==% '2')
  # every box checked on load = no filter, so every row shows
  (length(lti_rows(x)) %==% 4L)
  # unchecking "b" keeps only grp == "a" rows
  uncheck = 'var b = [...t.querySelectorAll(".lti-filters .lti-check input")]
               .find(i => i.value === "b"); b.checked = false; b.onchange()'
  (lti_rows(x, uncheck) %==% c('Rash', 'Headache'))
  # the expression box mirrors the set
  (lti_eval(x, 't.querySelector(".lti-filters .lti-pop .lti-search").value', uncheck)
   %==% '["a"].includes(x)')
})

assert('a "checklist" seeds a `selected` subset and chips when the column is hidden', {
  x = lt(tdf()) |> lt_hide(~ grp) |> lt_interactive(
    filter = list(grp = list(type = 'checklist', selected = 'a', label = 'Group')),
    pager = FALSE)
  # seeded to keep only "a" on load
  (lti_rows(x) %==% c('Rash', 'Headache'))
  # a hidden column renders as a chip; its summary names the single kept value
  (lti_eval(x, 't.querySelector(".lti-chip-name").textContent') %==% 'Group')
  (lti_eval(x, 't.querySelector(".lti-chip-cur").textContent') %==% 'a')
})

assert('LT.ui exposes the reusable popover, checklist, and chip builders', {
  x = itbl()
  (lti_eval(x, 'typeof LT.ui.popover + "," + typeof LT.ui.checklist + "," + typeof LT.ui.chip')
   %==% 'function,function,function')
  # the chip builder: a labelled wrapper that holds the caller's control and
  # exposes mark()/summarize(); its parts carry the same classes as a typed chip
  chip = 'var c = LT.ui.chip(document, "Group", document.createElement("button"));
    c.summarize("2 / 3"); c.mark(true); document.body.append(c.el);
    var el = document.querySelector("body > .lti-chip")'
  (lti_eval(x,
    '[el.querySelector(".lti-chip-name").textContent,
      el.querySelector(".lti-chip-cur").textContent,
      el.classList.contains("lti-on"),
      el.querySelector("button") !== null].join("|")', chip) %==% 'Group|2 / 3|true|true')
  # the checklist builder: labels of {value,label}, batch onInput of checked values
  build = 'window.OUT = null;
    var cl = LT.ui.checklist(document, [{value:"a",label:"A"},{value:"b",label:"B"}],
      v => window.OUT = v.join(","));
    document.body.append(...cl.el);
    var b = [...document.querySelectorAll("body > .lti-check input")]
      .find(i => i.value === "b"); b.checked = false; b.onchange()'
  (lti_eval(x, 'document.querySelectorAll("body > .lti-check").length + "|" + window.OUT', build)
   %==% '2|a')
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
