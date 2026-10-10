d = data.frame(a = 1:3, b = 4:6, c = 7:9)
x = lt(d)

assert("lt_header() sets header", {
  h = lt_header(x, "Title", "Sub")
  (h$header %==% list(title = "Title", subtitle = "Sub"))
  # NULL fields are dropped
  h2 = lt_header(x, "Title")
  (h2$header %==% list(title = "Title"))
})

assert("lt_spanner() with formula", {
  s = lt_spanner(x, Grp ~ b + c)
  (s$spanners %==% list(list(label = "Grp", columns = I(c("b", "c")))))
})

assert("lt_group(~ col, sep = TRUE) sets scalar row_group", {
  d2 = data.frame(g = c("A", "B", "A"), v = 1:3)
  g = lt(d2) |> lt_group(~ g, sep = TRUE)
  (g$row_group %==% "g")
})

assert("lt_group() manual groups add ops", {
  g = lt_group(x, "First" = 1:2, "Second" = 3L)
  (g$ops %==% list(
    list(type = "row_group", label = "First", rows = I(1:2)),
    list(type = "row_group", label = "Second", rows = I(3L))
  ))
})

assert("lt_footnote() builds correct location", {
  f = lt_footnote(x, "note", "column", ~ a)
  (f$footnotes %==% list(list(
    text = "note", location = list(type = "column_labels", columns = I("a"))
  )))

  f2 = lt_footnote(x, "note", "title")
  (f2$footnotes[[1]]$location %==% list(type = "title", group = "title"))

  f3 = lt_footnote(x, "note", "group", "G", match = "starts_with")
  (f3$footnotes[[1]]$location %==% list(
    type = "row_groups", match = "starts_with", value = "G"
  ))
})

assert("lt_footnote() covers all six locations", {
  # subtitle shares type "title" but a different group
  f1 = lt_footnote(x, "note", "subtitle")
  (f1$footnotes[[1]]$location %==% list(type = "title", group = "subtitle"))

  # spanner label
  f2 = lt_footnote(x, "note", "spanner", "S")
  (f2$footnotes[[1]]$location %==% list(
    type = "column_spanners", spanners = I("S")
  ))

  # row-group label (exact match is the default)
  f3 = lt_footnote(x, "note", "group", "G")
  (f3$footnotes[[1]]$location %==% list(
    type = "row_groups", match = "exact", values = I("G")
  ))

  # all row groups
  f4 = lt_footnote(x, "note", "group", match = "all")
  (f4$footnotes[[1]]$location %==% list(type = "row_groups", match = "all"))

  # body cells with specific rows
  f5 = lt_footnote(x, "note", "body", ~ a, rows = c(1, 2))
  (f5$footnotes[[1]]$location %==% list(
    type = "body", columns = I("a"), rows = I(c(1L, 2L))
  ))

  # body cells with all rows (rows stays NULL)
  f6 = lt_footnote(x, "note", "body", ~ a)
  (f6$footnotes[[1]]$location %==% list(
    type = "body", columns = I("a"), rows = NULL
  ))

  # an unknown location errors
  (has_error(lt_footnote(x, "note", "nope")))
})

assert("lt_note() appends notes", {
  n = lt_note(x, "Source: data") |> lt_note("Another note")
  (n$notes %==% list("Source: data", "Another note"))
})

assert("lt_align() supports numeric column indices", {
  a = lt_align(x, 1:2, "center")
  (a$ops[[1]]$columns %==% I(c("a", "b")))
})

assert("lt_format() records sig_digits and errors when combined with decimals", {
  f = lt_format(x, ~ a, sig_digits = 3)
  (f$ops[[1]]$sig_digits %==% 3)
  (is.null(f$ops[[1]]$decimals))
  (has_error(lt_format(x, ~ a, decimals = 2, sig_digits = 3)))
})

assert("lt_label() accepts a single named list or vector of labels", {
  expected = list(list(type = "label", labels = list(a = "Alpha", b = "Beta")))
  (lt_label(x, list(a = "Alpha", b = "Beta"))$ops %==% expected)
  (lt_label(x, c(a = "Alpha", b = "Beta"))$ops %==% expected)
  # named `...` still works and is not treated as a single-list argument
  (lt_label(x, a = "Alpha", b = "Beta")$ops %==% expected)
})

assert("lt_html() marks columns as raw HTML", {
  h = lt_html(x, ~ a + b)
  (h$html_cols %==% I(c("a", "b")))
  # no columns → whole table
  (lt_html(x)$html_cols %==% TRUE)
})

assert("lt_merge() requires 2+ columns", {
  err = tryCatch(lt_merge(x, ~ a), error = conditionMessage)
  (matches(err, ".*at least 2.*") %==% "")
})

assert("lt_merge() adds merge op", {
  m = lt_merge(x, ~ a + b, pattern = "{1} ({2})")
  (m$ops %==% list(list(
    type = "merge", columns = I(c("a", "b")), pattern = "{1} ({2})", hide = TRUE
  )))
})

assert("lt_style() builds CSS from arguments", {
  s = lt_style(x, "a", bold = TRUE, italic = TRUE, color = "red", bg = "#fff")
  css = s$ops[[1]]$css
  (matches(css, ".*font-weight:bold.*font-style:italic.*color:red.*background:#fff.*") %==% "")
})

assert("lt_style() with extra CSS properties", {
  s = lt_style(x, "a", borderLeft = "1px solid")
  (matches(s$ops[[1]]$css, ".*border-left:1px solid.*") %==% "")
})

assert("lt_style() with class and test", {
  s = lt_style(x, "a", test = "v => v > 1", class = "hi")
  (s$ops[[1]]$class %==% "hi")
  (class(s$ops[[1]]$test) %==% class(xfun::js("")))
})

assert("lt_style() returns unchanged if no css or class", {
  s = lt_style(x, "a")
  (length(s$ops) %==% 0L)
})

assert("lt_width() adds width op", {
  w = lt_width(x, a = "100px", b = "50%")
  (w$ops %==% list(list(type = "width", widths = list(a = "100px", b = "50%"))))

  # unnamed argument sets the whole-table width
  w = lt_width(x, "80%")
  (w$ops %==% list(list(type = "width", table = "80%")))

  # table width and column widths can be combined
  w = lt_width(x, "80%", a = "100px")
  (w$ops %==% list(list(
    type = "width", widths = list(a = "100px"), table = "80%"
  )))

  (has_error(lt_width(x, "80%", "90%")))
})

assert("lt_move() with after = NULL moves to start", {
  m = lt_move(x, ~ b, after = NULL)
  (m$ops %==% list(list(type = "move", columns = I("b"))))
})

# find the single op of a given type (NULL when there is none)
op_of = function(x, type) {
  ops = Filter(function(o) o$type == type, x$ops)
  if (length(ops)) ops[[1]]
}

assert("lt_errorbar() records columns, scale, and reference line", {
  # a two-sided formula: estimate on the LHS, bounds on the RHS. The value
  # column is recorded in `columns`; the bounds in `lowers`/`uppers`.
  e = lt_errorbar(x, a ~ b + c)
  op = op_of(e, "errorbar")
  (op$columns %==% I("a"))
  (op$lowers %==% I("b"))
  (op$uppers %==% I("c"))
  # default scale is the range of all three columns' values (1:9 here)
  (as.numeric(c(op$min, op$max)) %==% c(1, 9))
  # ref/axis are absent unless requested
  (is.null(op$ref) %==% TRUE)
  (is.null(op$axis) %==% TRUE)
  # a length-3 character vector names the same columns
  (op_of(lt_errorbar(x, c("a", "b", "c")), "errorbar")$columns %==% I("a"))
  # lower and upper are hidden by default, kept when hide = FALSE
  (op_of(e, "hide")$columns %==% I(c("b", "c")))
  (length(Filter(function(o) o$type == "hide", lt_errorbar(x, a ~ b + c, hide = FALSE)$ops)) %==% 0L)
  # explicit limits override the data range; ref and axis recorded when set
  op2 = op_of(lt_errorbar(x, a ~ b + c, limits = c(0, 10), ref = 0, axis = TRUE), "errorbar")
  (as.numeric(c(op2$min, op2$max)) %==% c(0, 10))
  (op2$ref %==% 0)
  (op2$axis %==% TRUE)
  (is.null(op2$axis_label) %==% TRUE)
  # a string axis enables the axis and is recorded as its caption
  op3 = op_of(lt_errorbar(x, a ~ b + c, axis = "Effect"), "errorbar")
  (op3$axis %==% TRUE)
  (op3$axis_label %==% "Effect")
  # each series must name exactly three columns
  (has_error(lt_errorbar(x, a ~ b)) %==% TRUE)
})

assert("lt_dotplot()/lt_errorbar() draw into a dedicated `into` column", {
  # `into` records the target name and an `add_col` op registers the new column;
  # every source column, including the first, is hidden
  e = lt_errorbar(x, a ~ b + c, into = "fig")
  (op_of(e, "errorbar")$into %==% "fig")
  (op_of(e, "add_col")$column %==% "fig")
  ("fig" %in% names(e$data) %==% FALSE)
  (op_of(e, "hide")$columns %==% I(c("a", "b", "c")))
  # hide = FALSE keeps every value column visible alongside the plot column
  (length(Filter(function(o) o$type == "hide",
    lt_errorbar(x, a ~ b + c, into = "fig", hide = FALSE)$ops)) %==% 0L)
  # the merged multi-series header labels the `into` column, not the first value
  x3 = lt(data.frame(a = 1:3, b = 4:6, c = 7:9, d = 2:4, e = 1:3, f = 5:7))
  e2 = lt_errorbar(x3, a ~ b + c, d ~ e + f, into = "fig")
  (op_of(e2, "label")$labels[["fig"]] %==% "a / d")
  # into omitted: unchanged (no `into` key, no add_col op)
  eb0 = lt_errorbar(x, a ~ b + c)
  (is.null(op_of(eb0, "errorbar")$into) %==% TRUE)
  (is.null(op_of(eb0, "add_col")) %==% TRUE)

  # dotplot behaves the same: scalar name + add_col op, all sources hidden
  p = lt_dotplot(x, ~ a + b + c, into = "plot")
  (op_of(p, "dotplot")$into %==% "plot")
  (op_of(p, "add_col")$column %==% "plot")
  (op_of(p, "hide")$columns %==% I(c("a", "b", "c")))
  (op_of(p, "label")$labels[["plot"]] %==% "a / b / c")

  # when `into` is an existing column, it is never hidden (it holds the plot)
  # and no `add_col` op is emitted (the column already exists)
  q = lt_dotplot(x, ~ a + b + c, into = "b")
  (op_of(q, "hide")$columns %==% I(c("a", "c")))
  (is.null(op_of(q, "add_col")) %==% TRUE)
})

assert("lt_errorbar() stacks several series with colors and a legend", {
  # one triple per series via ...: one point-and-bar per series, stacked in each
  # cell. The first value column holds the plot; the rest are hidden; headers
  # merge.
  x3 = lt(data.frame(a = 1:3, b = 4:6, c = 7:9, d = 2:4, e = 1:3, f = 5:7))
  e = lt_errorbar(x3, a ~ b + c, d ~ e + f, color = TRUE,
    labels = c("Arm 1", "Arm 2"))
  op = op_of(e, "errorbar")
  (op$columns %==% I(c("a", "d")))
  (op$lowers %==% I(c("b", "e")))
  (op$uppers %==% I(c("c", "f")))
  (op$labels %==% I(c("Arm 1", "Arm 2")))
  (length(op$colors) %==% 2L)
  # scale spans every column's values; default height grows with series count
  (as.numeric(c(op$min, op$max)) %==% c(1, 9))
  (op$height %==% (2 * 9 + 4))
  # every column but the first value column is hidden
  (op_of(e, "hide")$columns %==% I(c("b", "c", "d", "e", "f")))
  # the merged header labels the first value column with all value names
  (op_of(e, "label")$labels[["a"]] %==% "a / d")
  # labels must match the series count
  (has_error(lt_errorbar(x3, a ~ b + c, d ~ e + f, labels = "one")) %==% TRUE)
})

assert("lt_dotplot() records one dot per column, colors, and a legend", {
  # the plot keeps every named column; the scale spans all their values (1:9)
  op = op_of(lt_dotplot(x, ~ a + b + c), "dotplot")
  (op$columns %==% I(c("a", "b", "c")))
  (as.numeric(c(op$min, op$max)) %==% c(1, 9))
  # an axis is drawn by default; monochrome (no colors/labels) unless requested
  (op$axis %==% TRUE)
  (is.null(op$colors) %==% TRUE)
  (is.null(op$labels) %==% TRUE)
  # the first column's header is labeled with all the column names joined, since
  # the plot shows them all (not just the first)
  (op_of(lt_dotplot(x, ~ a + b + c), "label")$labels %==% list(a = "a / b / c"))
  # columns after the first are hidden by default, kept when hide = FALSE
  (op_of(lt_dotplot(x, ~ a + b + c), "hide")$columns %==% I(c("b", "c")))
  (length(Filter(function(o) o$type == "hide",
    lt_dotplot(x, ~ a + b + c, hide = FALSE)$ops)) %==% 0L)

  # color = TRUE pulls one palette color per column and labels the legend with
  # the column names
  pal = op_of(lt_dotplot(x, ~ a + b + c, color = TRUE), "dotplot")
  (unclass(pal$colors) %==% rep_len(grDevices::palette(), 3))
  (unclass(pal$labels) %==% c("a", "b", "c"))

  # a character vector sets colors verbatim (recycled); labels can be overridden
  cus = op_of(lt_dotplot(x, ~ a + b, color = c("red", "blue"),
    labels = c("X", "Y")), "dotplot")
  (unclass(cus$colors) %==% c("red", "blue"))
  (unclass(cus$labels) %==% c("X", "Y"))
  # a mismatched labels length errors
  (has_error(lt_dotplot(x, ~ a + b, color = TRUE, labels = "only-one")) %==% TRUE)

  # axis = FALSE drops the axis; a string axis is recorded as its caption
  (is.null(op_of(lt_dotplot(x, ~ a, axis = FALSE), "dotplot")$axis) %==% TRUE)
  (op_of(lt_dotplot(x, ~ a, axis = "Score"), "dotplot")$axis_label %==% "Score")

  # stagger is off by default (absent) and grows the default height when on
  (is.null(op_of(lt_dotplot(x, ~ a + b + c), "dotplot")$stagger) %==% TRUE)
  (op_of(lt_dotplot(x, ~ a + b + c), "dotplot")$height %==% 16)
  st = op_of(lt_dotplot(x, ~ a + b + c, stagger = TRUE), "dotplot")
  (st$stagger %==% TRUE)
  (st$height %==% (3 * 9 + 4))
  # an explicit height overrides the staggered default
  (op_of(lt_dotplot(x, ~ a + b + c, stagger = TRUE, height = 20),
    "dotplot")$height %==% 20)
})

assert("lt_css() stores inline rules", {
  c1 = lt_css(x, .na = "background: #eee")
  (c1$rules %==% "  .na { background: #eee }")
})

assert("lt_css() with list-style rules", {
  c1 = lt_css(x, .hi = list(color = "red", fontWeight = "bold"))
  (c1$rules %==% "  .hi { color: red; font-weight: bold; }")
})

assert("lt_css() resolves bundled stylesheets", {
  c1 = lt_css(x, "lt.css")
  (length(c1$css) %==% 1L)
  (file.exists(c1$css[1]))
})

assert("lt_css() handles absolute, relative, and URL paths", {
  tmp = tempfile(fileext = ".css")
  writeLines("td{}", tmp)
  c1 = lt_css(x, tmp)
  (c1$css %==% tmp)
  unlink(tmp)
  c2 = lt_css(x, "https://example.com/theme.css")
  (c2$css %==% "https://example.com/theme.css")
  # a relative path to an existing file is kept relative (portable)
  d = tempfile(); dir.create(d)
  writeLines("td{}", file.path(d, "times.css"))
  owd = setwd(d); on.exit({setwd(owd); unlink(d, recursive = TRUE)})
  (lt_css(x, "times.css")$css %==% "times.css")
})


assert("lt_wrap() appends class across repeated calls", {
  # class from a later call is appended to an earlier one (JS prepends lt-wrap)
  (lt_wrap(lt_wrap(x, class = "foo"), class = "bar")$wrap$class %==% "foo bar")
})
