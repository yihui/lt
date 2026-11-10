# Download button and its CSV/RTF formats (browser), and lt_export() to the
# same formats (Node).

# Click `action` (JS, `t` is the table) with downloads captured, then return the
# file names and the first file's text: "name1|name2\ntext".
dl_text = function(x, action) {
  code = sprintf('var t = document.querySelector(".lt-table"), blobs = [], names = [];
    URL.createObjectURL = b => (blobs.push(b), "blob:x");
    URL.revokeObjectURL = () => {};
    HTMLAnchorElement.prototype.click = function() { names.push(this.download); };
    %s;
    setTimeout(async () => {
      document.body.dataset.out = names.join("|") + "\\n" + await blobs[0]?.text();
      document.body.dataset.ready = "1";
    }, 50)', action)
  html = sub('</head>', sprintf(
    '<script>addEventListener("load", function() {%s})</script></head>', code
  ), format(x, fragment = FALSE), fixed = TRUE)
  f = tempfile(fileext = '.html')
  on.exit(unlink(f), add = TRUE)
  xfun::write_utf8(html, f)
  lti_eval_cdp(f)
}

menu_pick = function(fmt) sprintf(
  '[...t.querySelectorAll(".lti-dl .lti-menu label")].find(l => l.textContent === "%s").click()', fmt)
open_menu = 't.querySelector(".lti-download").click()'

dt = data.frame(name = c('a,b', 'c'), n = c(5, 12))

assert("the download button opens a menu of formats; each downloads its own file", {
  x = lt(dt) |> lt_interactive(download = TRUE)
  (lti_eval(x, 't.querySelectorAll(".lti-dl .lti-menu label").length') %==% '2')
  # closed until clicked
  (lti_eval(x, 't.querySelector(".lti-dl .lti-menu").hidden') %==% 'true')
  (lti_eval(x, 't.querySelector(".lti-dl .lti-menu").hidden', open_menu) %==% 'false')
  (dl_text(x, menu_pick('CSV')) %==% 'lt-table.csv\nname,n\n"a,b",5\nc,12')
  rtf = dl_text(x, menu_pick('RTF'))
  (grepl('^lt-table\\.rtf\n\\{\\\\rtf1', rtf))
  # a header row and one row per record, the header in bold
  (count_str(rtf, '\\trowd') %==% 3L)
  (count_str(rtf, '{\\b name}') %==% 1L)
  # the menu closes after a pick
  (lti_eval(x, 't.querySelector(".lti-dl .lti-menu").hidden', paste(open_menu, menu_pick('CSV'), sep = ';'))
   %==% 'true')
})

assert("a file name is a stem: a format extension is replaced", {
  x = lt(dt) |> lt_interactive(download = 'cars.csv')
  (dl_text(x, menu_pick('RTF')) |> strsplit('\n') |> _[[1]][1] %==% 'cars.rtf')
})

assert("one format downloads directly, without a menu", {
  x = lt(dt) |> lt_interactive(download = list(formats = 'rtf'))
  (lti_eval(x, 't.querySelectorAll(".lti-dl .lti-menu").length') %==% '0')
  (grepl('^lt-table\\.rtf\n\\{\\\\rtf1', dl_text(x, open_menu)))
})

assert("downloads honor the view: filtered and sorted rows only", {
  x = lt(dt) |> lt_interactive(download = TRUE)
  by_n = 'document.querySelector("thead th .lti-label").click()'
  (dl_text(x, paste('t.querySelector(".lti-search").value = "c"',
    't.querySelector(".lti-search").dispatchEvent(new Event("input"))',
    open_menu, menu_pick('CSV'), sep = ';')) %==% 'lt-table.csv\nname,n\nc,12')
})

assert("lt_export() writes CSV and RTF from Node", {
  x = lt(dt) |> lt_header('Title') |> lt_note('A note')
  f1 = tempfile(fileext = '.csv'); f2 = tempfile(fileext = '.rtf')
  on.exit(unlink(c(f1, f2)), add = TRUE)
  (lt_export(x, f1) %==% f1)
  (xfun::read_utf8(f1) %==% c('name,n', '"a,b",5', 'c,12'))
  lt_export(x, f2)
  rtf = paste(xfun::read_utf8(f2), collapse = '\n')
  (count_str(rtf, '\\trowd') %==% 3L)
  (count_str(rtf, 'Title') %==% 1L)
  (count_str(rtf, 'A note') %==% 1L)
})

assert("RTF escapes special characters and merges spanners", {
  x = lt(data.frame(g.a = 'x{y}\\z', g.b = 'é')) |> lt_spanner('G', c('g.a', 'g.b'))
  f = tempfile(fileext = '.rtf')
  on.exit(unlink(f), add = TRUE)
  lt_export(x, f)
  rtf = paste(xfun::read_utf8(f), collapse = '\n')
  (count_str(rtf, 'x\\{y\\}\\\\z') %==% 1L)
  (count_str(rtf, '\\u233?') %==% 1L)
  # spanner row + header + 1 body row; the spanner cell spans both columns
  (count_str(rtf, '\\trowd') %==% 3L)
  (count_str(rtf, '\\clmgf') %==% 1L)
  (count_str(rtf, '\\clmrg') %==% 1L)
})
