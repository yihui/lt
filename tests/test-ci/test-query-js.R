# Plain-language query module (lt-query.js) in Node.js. The runner loads it the
# way a page does (LT.plugins.query) and prints the reading, the expression, and
# whether anything beyond plain text was read.

PARSE = '
const fs = require("fs"), vm = require("vm"), ctx = {};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8").split("(window)").join("(globalThis)"), ctx);
vm.runInContext(fs.readFileSync(process.argv[3], "utf8"), ctx);
const Q = ctx.LT.plugins.query, inp = JSON.parse(fs.readFileSync(0, "utf8"));
const t = Q.parse(inp.query, inp.names || {}, inp.col0 ?? null);
process.stdout.write([Q.text(t), Q.expr(t) ?? "", String(Q.parsed(t))].join("\\n"));
'

# list(text, expr, parsed) for a query; `names` maps names/labels to columns
read_query = function(query, names = c(name = 'name', price = 'price', color = 'color'),
                      col0 = NULL) {
  runner = tempfile(fileext = '.js')
  writeLines(PARSE, runner)
  on.exit(unlink(runner), add = TRUE)
  input = xfun::tojson(list(query = query, names = as.list(names), col0 = col0))
  out = system2(
    'node', shQuote(c(runner, asset_path('lt.js'), asset_path('lt-query.js'))),
    input = input, stdout = TRUE
  )
  list(text = out[1], expr = out[2], parsed = out[3] == 'TRUE')
}

assert('operators and their phrasings map to expressions', {
  (read_query('price>100')$expr %==% 'x > 100')
  (read_query('price over 100')$expr %==% 'x > 100')
  (read_query('price at least 2.5')$expr %==% 'x >= 2.5')
  (read_query('price under 9')$expr %==% 'x < 9')
  (read_query('price at most 9')$expr %==% 'x <= 9')
  (read_query('price is 200')$expr %==% 'x == 200')
  (read_query("color is not red")$expr %==% 'String(x).toLowerCase() != "red"')
  (read_query("color does not contain red")$expr %==% '!String(x).toLowerCase().includes("red")')
  (read_query("color doesn't contain red")$text %==% 'color: x does not contain "red"')
  # without a column, no cell may contain the text
  (read_query("excludes red")$expr %==% '!String(x).toLowerCase().includes("red")')
  (read_query('price between 100 and 160')$expr %==% 'x >= 100 && x <= 160')
  (read_query('price:5')$text %==% 'price: "5"')
  (read_query('price over 1,000')$expr %==% 'x > 1000')
})

assert('labels with spaces name a column; longest match wins', {
  nm = c('Sepal Length' = 'sepal_length', 'sepal_length' = 'sepal_length')
  (read_query('sepal length over 5', nm)$text %==% 'sepal_length: x > 5')
  (read_query('"Sepal Length" at least 3', nm)$expr %==% 'x >= 3')
  (read_query('sepal_length over 5', nm)$text %==% 'sepal_length: x > 5')
})

assert('commas and semicolons separate clauses, not literal text', {
  (read_query('price over 20, color is red')$text %==% 'price: x > 20 and color: x == "red"')
  (read_query('price over 20; color is red')$text %==% 'price: x > 20 and color: x == "red"')
})

assert('or alternates; and binds tighter than or', {
  p = read_query('price over 20 or color is red and price under 5')
  (p$text %==% 'price: x > 20 or (color: x == "red" and price: x < 5)')
  (p$expr %==% '(x > 20) || ((String(x).toLowerCase() == "red") && (x < 5))')
  (read_query('"new york" or boston')$text %==% '"new york" or "boston"')
  (read_query('red blue')$text %==% '"red" and "blue"')
})

assert('an x inside quotes or in a condition does not make the query an expression', {
  (read_query('price over 5, color is x')$text %==% 'price: x > 5 and color: x == "x"')
  (read_query('name contains "box x"')$text %==% 'name: "box x"')
  (read_query('name contains "box x"')$expr %==% '')
})

assert('a column name alone is free text; text with nothing read is plain', {
  (read_query('color')$parsed %==% FALSE)
  (read_query('x > 5')$expr %==% 'x > 5')
  (read_query('price>abc')$text %==% '"price>abc"')
  (read_query('!rash')$text %==% '"!rash"')
  (read_query('!rash')$parsed %==% FALSE)
})

assert("a column's own box takes a condition without the column name", {
  p = read_query('over 100 or under 5', names = c(), col0 = 'price')
  (p$expr %==% '(x > 100) || (x < 5)')
  (read_query('rash', names = c(), col0 = 'name')$parsed %==% FALSE)
})

assert('contains takes the whole phrase, even with special characters', {
  (read_query('name contains ~HR at bound')$text %==% 'name: "~HR at bound"')
  (read_query('name has p (1-sided)')$text %==% 'name: "p (1-sided)"')
  (read_query('name does not contain p (1-sided)')$expr %==% '!String(x).toLowerCase().includes("p (1-sided)")')
  (read_query('name contains ~HR at bound, price over 5')$text %==% 'name: "~HR at bound" and price: x > 5')
})
