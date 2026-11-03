// Run lt.js in Node: JSON spec from stdin, rendered HTML to stdout.
// argv[2..]: runtime scripts to load into one shared root, in order (e.g.
// lt-plot.js before lt.js, so plot renderer is registered when core drains
// its queue).
const fs = require('fs'), vm = require('vm');
const root = {};
for (let i = 2; i < process.argv.length; i++) {
  const src = fs.readFileSync(process.argv[i], 'utf8');
  vm.runInNewContext(src.replace('(window)', '(root)'), { root });
}
const raw = fs.readFileSync(0, 'utf8');
const spec = eval('(' + raw + ')');
if (spec.data) for (const k of Object.keys(spec.data)) {
  if (!Array.isArray(spec.data[k])) spec.data[k] = [spec.data[k]];
}
// Revive test functions from strings (style ops)
for (const op of (spec.ops || [])) {
  if (typeof op.test === 'string') op.test = eval(op.test);
}
process.stdout.write(root.LT.buildHtml(spec));
