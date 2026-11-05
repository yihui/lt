# Sticky header inside a scrolling .lt-wrap (browser).

wide = function() {
  d = as.data.frame(matrix(1:600, 30, 20, dimnames = list(NULL, paste0('col', 1:20))))
  lt(d) |> lt_wrap(style = 'width:300px;max-height:150px')
}
# <thead> top, relative to the wrap
probe = '(() => {
  const r = t.closest(".lt-wrap").getBoundingClientRect();
  return Math.round(t.tHead.getBoundingClientRect().top - r.top)
})()'
scroll = 'var w = t.closest(".lt-wrap"); w.scrollTop = 100'

assert("the whole header stays put while the wrap scrolls", {
  # scrolled 100px down, the header stays at the wrap's top edge
  (lti_eval(wide(), probe, scroll) %==% '0')
  # with a spanner row, and in an interactive table (search/filter rows)
  (lti_eval(lt_spanner(wide(), 's', c('col1', 'col2')), probe, scroll) %==% '0')
  (lti_eval(lt_interactive(wide()), probe, scroll) %==% '0')
})

assert("a cell's own background wins over the sticky one", {
  x = wide() |> lt_style(columns = 'col1', test = 'v => v > 0', class = 'hot') |>
    lt_css(td.hot = 'background: rgb(255, 0, 0)')
  (lti_eval(x, 'getComputedStyle(t.querySelector("tbody td")).backgroundColor') %==%
    'rgb(255, 0, 0)')
})

assert("a printed standalone table scrolls inside .lt-wrap, not the page", {
  x = lt(as.data.frame(matrix(1:600, 150, 4)))
  # the page fits the viewport while the wrap holds the overflow
  (lti_eval(x, 'document.documentElement.scrollHeight <= innerHeight', html = view_html(x))
   %==% 'true')
  (lti_eval(x, 't.closest(".lt-wrap").scrollHeight > t.closest(".lt-wrap").clientHeight',
            html = view_html(x)) %==% 'true')
  # the default document (no print styling) overflows the page
  (lti_eval(x, 'document.documentElement.scrollHeight > innerHeight') %==% 'true')
})
