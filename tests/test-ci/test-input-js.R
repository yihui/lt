# Editable cells (browser). lt-input.js is injected after load; it enhances
# the table already mounted, as lt_input() does.

edit = function(x, expr, js = '') lti_eval(
  x, expr, paste(xfun::file_string(asset_path('lt-input.js')), js, sep = ';')
)
# type `v` into body cell (row r, column ci), then leave it
type = function(r, ci, v) sprintf(
  'var td = t.tBodies[0].rows[%d].cells[%d]; td.focus(); td.textContent = "%s"; td.blur()',
  r, ci, v
)

x = lt(data.frame(a = c(1, 2), b = c('x', 'y')))
x$input = I('a')

assert('only the listed columns are editable', {
  (edit(x, 't.querySelectorAll("td[contenteditable]").length') %==% '2')
  (edit(x, 't.tBodies[0].rows[0].cells[1].isContentEditable') %==% 'false')
})

assert('edits write back to the data, typed by column', {
  (edit(x, 't._ltSpec.data.a.join()', type(1, 0, '9')) %==% '1,9')
  # non-numeric text is rejected: the previous value is restored
  (edit(x, 't._ltSpec.data.a.join()', type(1, 0, 'abc')) %==% '1,2')
  (edit(x, 't.tBodies[0].rows[1].cells[0].textContent', type(1, 0, 'abc')) %==% '2')
  # an empty numeric cell is missing
  (edit(x, 'JSON.stringify(t._ltSpec.data.a)', type(0, 0, '')) %==% '[null,2]')
})

assert('text columns keep strings', {
  x$input = I('b')
  (edit(x, 't._ltSpec.data.b.join()', type(0, 1, '12')) %==% '12,y')
})
