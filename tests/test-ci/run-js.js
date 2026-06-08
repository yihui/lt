// Load lt.js in Node.js and run buildHtml() on a JSON spec from stdin.
const fs = require('fs'), vm = require('vm');
const src = fs.readFileSync(process.argv[2], 'utf8');
const root = {};
vm.runInNewContext(src.replace('(window)', '(root)'), { root });
const spec = JSON.parse(fs.readFileSync(0, 'utf8'));
// Normalize: ensure data columns are arrays (JSON scalars become primitives)
if (spec.data) for (const k of Object.keys(spec.data)) {
  if (!Array.isArray(spec.data[k])) spec.data[k] = [spec.data[k]];
}
// Revive test functions from strings
for (const op of (spec.ops || [])) {
  if (typeof op.test === 'string') op.test = eval(op.test);
}
process.stdout.write(root.LT.buildHtml(spec));
