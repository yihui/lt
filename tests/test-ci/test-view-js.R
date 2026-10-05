# Interactive view pipeline in Node.js: numeric/string/multi-key sort,
# substring and expression search, per-column filters, AND composition, paging.

assert("numeric sort orders by raw value; nulls sort last both directions", {
  d = list(name = sym, n = c(5, 12, 3, 8))
  (run_view(d, by(k('n', 'asc'))) %==% c(3L, 1L, 4L, 2L))
  (run_view(d, by(k('n', 'desc'))) %==% c(2L, 4L, 1L, 3L))
  d2 = list(n = c(5, NA, 3))
  (run_view(d2, by(k('n', 'asc'))) %==% c(3L, 1L, 2L))
  (run_view(d2, by(k('n', 'desc'))) %==% c(1L, 3L, 2L))
})

assert("string columns sort locale-aware (case-insensitive letter order)", {
  d = list(g = c("banana", "Apple", "cherry"))
  (run_view(d, by(k('g', 'asc'))) %==% c(2L, 1L, 3L))
})

assert("several sort keys break ties in order", {
  d = list(g = c("a", "a", "b", "b"), v = c(2, 1, 1, 2))
  # g ascending, then v descending within each group
  (run_view(d, by(k('g'), k('v', 'desc'))) %==% c(1L, 2L, 4L, 3L))
  # g ascending, then v ascending
  (run_view(d, by(k('g'), k('v'))) %==% c(2L, 1L, 3L, 4L))
  # a later key only decides rows the earlier ones tie on
  (run_view(d, by(k('v'), k('g'))) %==% c(2L, 3L, 1L, 4L))
})

assert("substring search matches display text; leading ! negates", {
  d = list(name = sym, n = c(5, 12, 3, 8))
  (run_view(d, list(term = 'rash')) %==% 1L)                # case-insensitive
  (run_view(d, list(term = '!rash')) %==% c(2L, 3L, 4L))
  (run_view(d, list(term = 'a')) %==% c(1L, 2L, 3L))        # Itch has no 'a'
  (run_view(d, list(term = '')) %==% 1:4)                   # empty ⇒ all rows
})

assert("expression mode evaluates raw values (numbers and strings)", {
  d = list(name = sym, n = c(5, 12, 3, 8))
  (run_view(d, list(term = 'x > 5')) %==% c(2L, 4L))        # n = 12, 8
  # negation (!=) keeps a row only when every searched cell satisfies it
  (run_view(d, list(term = 'x !== "Rash"')) %==% c(2L, 3L, 4L))
})

assert("substring matches display while expression matches the raw value", {
  # raw 1000, displayed with a thousands separator
  d = list(v = 1000)
  disp = list(v = "1 000")
  (run_view(d, list(term = '1 000'), disp) %==% 1L)          # matches display
  (run_view(d, list(term = '1000'), disp) %==% integer(0))   # display has a space
  (run_view(d, list(term = 'x > 500'), disp) %==% 1L)        # expression on raw
})

assert("search and sort compose (filter then sort)", {
  d = list(name = sym, n = c(5, 12, 3, 8))
  # keep rows containing 'a' (1,2,3), then sort by n descending: 12,5,3
  (run_view(d, c(list(term = 'a'), by(k('n', 'desc')))) %==% c(2L, 1L, 3L))
})

assert("a column filter looks only at its own column", {
  d = list(name = sym, n = c(5, 12, 3, 8))
  (run_view(d, list(filters = list(name = 'a'))) %==% c(1L, 2L, 3L))
  (run_view(d, list(filters = list(n = 'x > 5'))) %==% c(2L, 4L))
  # '1' is in the display of n = 12 only; the names are not searched
  (run_view(d, list(filters = list(n = '1'))) %==% 2L)
})

assert("filters and the search are combined with AND", {
  d = list(name = sym, n = c(5, 12, 3, 8))
  # 'a' in name keeps 1,2,3; n > 5 keeps 2,4
  (run_view(d, list(filters = list(name = 'a', n = 'x > 5'))) %==% 2L)
  (run_view(d, list(filters = list(name = 'a'), term = 'x > 5')) %==% 2L)
  (run_view(d, list(filters = list(name = 'a', n = 'x > 100'))) %==% integer(0))
})

assert("row groups sort and filter within each group, keeping group order", {
  d = list(g = c("a", "a", "b", "b"), v = c(2, 1, 4, 3))
  spec = list(`_groups` = list(
    list(label = "a", rows = I(1:2)), list(label = "b", rows = I(3:4))
  ))
  # sort v ascending within each group; the groups stay a-before-b
  (run_view(d, by(k('v')), spec = spec) %==% c(2L, 1L, 4L, 3L))
  (run_view(d, by(k('v', 'desc')), spec = spec) %==% c(1L, 2L, 3L, 4L))
  # a filter can empty a whole group: keep v < 3 (only group a) or v >= 3 (b)
  (run_view(d, list(term = 'x < 3'), spec = spec) %==% c(1L, 2L))
  (run_view(d, list(term = 'x >= 3'), spec = spec) %==% c(3L, 4L))
})

assert("manual groups need not cover every row; the rest trail ungrouped", {
  d = list(v = 1:3)
  # only rows 1 and 3 are grouped; row 2 is ungrouped and comes last
  spec = list(`_groups` = list(list(label = "g", rows = I(c(1L, 3L)))))
  (run_view(d, list(), spec = spec) %==% c(1L, 3L, 2L))
})

assert("indentation builds a tree; a sort reorders siblings within a parent", {
  # 1:A(0) 2:A2(1) 3:A1(1) 4:B(0) 5:B1(1)
  d = list(v = c("A", "A2", "A1", "B", "B1"), n = c(3, 2, 1, 5, 4))
  spec = list(`_indent` = c(0, 1, 1, 0, 1))
  (run_view(d, list(), spec = spec) %==% 1:5)                       # file order
  # sort n ascending: parents 1,4 keep their order; row 1's children sort
  # (row 3 n=1 before row 2 n=2), with each subtree carried along
  (run_view(d, by(k('n')), spec = spec) %==% c(1L, 3L, 2L, 4L, 5L))
})

assert("filtering an indented table keeps a match's ancestors for context", {
  d = list(v = c("A", "A1", "A2", "B", "B1"), n = c(3, 1, 2, 5, 4))
  spec = list(`_indent` = c(0, 1, 1, 0, 1))
  # only row 2 matches (n == 1); its parent (row 1) stays, the B subtree goes
  (run_view(d, list(term = 'x == 1'), spec = spec) %==% c(1L, 2L))
})

assert("rowspan groups sort within each run; a group key reorders blocks", {
  d = list(g = c("a", "a", "b", "b"), v = c(2, 1, 4, 3))
  spec = list(`_rowspan` = I("g"))
  # a data key sorts within each run only (the blocks keep file order)
  (run_view(d, by(k('v')), spec = spec) %==% c(2L, 1L, 4L, 3L))
  # the group column as a key reorders whole blocks (rows keep file order in them)
  (run_view(d, by(k('g', 'desc')), spec = spec) %==% c(3L, 4L, 1L, 2L))
  # group key + data key compose: blocks by g desc, rows by v asc within each
  (run_view(d, by(k('g', 'desc'), k('v')), spec = spec) %==% c(4L, 3L, 2L, 1L))
  # a filter can empty a block: v < 3 keeps only group a
  (run_view(d, list(term = 'x < 3'), spec = spec) %==% c(1L, 2L))
})

assert("nested rowspan groups stay hierarchical: an inner key stays in its parent", {
  d = list(g1 = c("a", "a", "a", "b"), g2 = c("x", "x", "y", "z"),
           v = c(3, 1, 2, 4))
  spec = list(`_rowspan` = I(c("g1", "g2")))
  # sort v descending: only leaves within the innermost (g1, g2) block reorder,
  # so g1=a,g2=x (rows 1,2) swaps to 1,2 and nothing crosses a block boundary
  (run_view(d, by(k('v', 'desc')), spec = spec) %==% c(1L, 2L, 3L, 4L))
  # sort g2 descending: within g1=a its g2 blocks reorder (y before x), the
  # leaves within each untouched; g1 blocks and ungrouped tail stay put
  (run_view(d, by(k('g2', 'desc')), spec = spec) %==% c(3L, 1L, 2L, 4L))
})

assert("paging slices the view and clamps the page into range", {
  d = list(n = 1:7)
  (run_page(d, list(pageSize = 3))$rows %==% 1:3)
  (run_page(d, list(pageSize = 3, page = 1))$rows %==% 4:6)
  (run_page(d, list(pageSize = 3, page = 2))$rows %==% 7L)
  # the pager's "last" step asks for a page past the end
  p = run_page(d, list(pageSize = 3, page = 99))
  (p$rows %==% 7L)
  (p$page %==% 2L)
  # a filter can leave fewer rows than the current page holds
  p = run_page(d, list(pageSize = 3, page = 2, term = 'x < 3'))
  (p$rows %==% 1:2)
  (p$page %==% 0L)
  # no matches at all: the first page of nothing
  p = run_page(d, list(pageSize = 3, page = 2, term = 'zzz'))
  (p$rows %==% integer(0))
  (p$page %==% 0L)
  # a page size of 0 (Inf in R) is one page holding every row
  p = run_page(d, list(pageSize = 0, page = 2))
  (p$rows %==% 1:7)
  (p$page %==% 0L)
})
