// Run lt.js in Node: JSON spec from stdin, rendered HTML to stdout.
// argv[2..]: runtime scripts to load into one shared root, in order (e.g.
// lt-plot.js before lt.js, so plot renderer is registered when core drains
// its queue). With `--export=fmt` (needs lt-export.js), print the table in that
// format (e.g. csv, rtf) instead of HTML.
const fs = require('fs'), vm = require('vm');
const root = {}, args = process.argv.slice(2);
const fmt = (args.find(a => a.startsWith('--export=')) || '').slice(9);
for (const f of args.filter(a => !a.startsWith('--'))) {
  const src = fs.readFileSync(f, 'utf8');
  vm.runInNewContext(src, { window: root });
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
const html = root.LT.buildHtml(spec);
process.stdout.write(fmt ? root.LT.plugins.export.text(fmt, spec) : html);
