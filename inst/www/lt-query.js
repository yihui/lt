/* lt-query.js — read a plain-language query ("price over 20, brand is foo or
 * bar") into a filter tree. Standalone: no DOM, no lt; the lt-interactive.js
 * search boxes use it, and so can any page or Node project:
 *   const Q = require("./lt-query.js");               // Node, bundlers
 *   LT.plugins.query                                   // browser, via a <script>
 *
 *   Q.parse(query, names?, col0?) -> tree | null
 *   Q.text(tree, label?)          -> readable one-line summary
 *   Q.expr(tree)                  -> one JS expression over `x`, or null
 *   Q.parsed(tree)                -> true if more than plain text was read
 *
 * A tree is a leaf `{col, term, show?, free?}` or `{op: "and" | "or", items}`. `term` is
 * either text to find (a leading `!` negates) or, if it uses `x`, a JS
 * expression on the cell value (`x > 5`). `col` is null for "any column".
 *
 * Syntax (case-insensitive). Conditions name a column (`names` maps each name or
 * label, which may contain spaces, to its column) then an operator and a value:
 *   over above more than greater than > | at least >= | under below less than
 *   fewer than < | at most up to <= | is equals = | is not not other than !=
 *   | between 5 and 10 | contains has : | `col value` alone means contains
 * Conditions combine with `and`, `,` or `;` (all must hold); `or` alternates.
 * Other words are free text, each must be found; "quote" a phrase. With `col0`,
 * the condition needs no column name and free text belongs to that column. Text
 * using `x` (an expression) is kept whole.
 */
(root => {
  "use strict";

  // Operator phrases per canonical operator.
  const OPS = {
    ":": ["contains", "has", ":"],
    ">": ["greater than", "more than", "bigger than", "larger than", "above", "over", ">"],
    ">=": ["at least", "greater than or equal to", ">="],
    "<": ["less than", "smaller than", "fewer than", "below", "under", "<"],
    "<=": ["at most", "no more than", "up to", "less than or equal to", "<="],
    "==": ["is", "equals", "equal to", "=", "=="],
    "!=": ["is not", "isn't", "not", "other than", "!="],
    between: ["between"]
  };
  // Longest phrase first, so "is not" beats "is"
  const PHRASES = Object.entries(OPS).flatMap(([op, ps]) => ps.map(p => [p.split(" "), op]))
    .sort((a, b) => b[0].length - a[0].length);
  // Token: "quoted" | operator | separator (`;`, or `,` before a space) | word (a
  // comma inside a number stays) | any other character
  const LEX = /"([^"]*)"|(>=|<=|!=|==|[<>=:])|(;|,(?=\s|$))|((?:!(?!=))?(?:,(?=\S)|[^\s"<>=!:;,])+)|(\S)/g;

  const isExpr = v => /(^|[^\w$])x([^\w$]|$)/.test(v);
  // number text without thousands separators (`1,000` -> `1000`)
  const num = v => v.replace(/(?<=\d),(?=\d{3}\b)/g, "");
  const isNum = v => v.trim() !== "" && isFinite(num(v));
  const norm = s => String(s).trim().split(/\s+/).join(" ").toLowerCase();
  const lower = t => t?.t.toLowerCase();

  function parse(query, names = {}, col0 = null) {
    const raw = String(query ?? "").trim();
    if (!raw) return null;
    if (isExpr(raw)) return { col: col0, term: raw, free: true };
    // kind: q quoted, o operator, s separator, w word
    const toks = [...raw.matchAll(LEX)].map(m => ({
      t: m[1] ?? m[0], s: m.index, e: m.index + m[0].length,
      k: m[1] != null ? "q" : m[2] ? "o" : m[3] ? "s" : "w"
    }));
    // name/label -> column, matched on up to `maxK` tokens (labels hold spaces)
    const byName = new Map(Object.entries(names).map(([n, c]) => [norm(n), c])),
          maxK = Math.max(1, ...[...byName.keys()].map(n => n.split(" ").length));
    const named = i => {
      for (let k = Math.min(maxK, toks.length - i); k > 0; k--) {
        const part = toks.slice(i, i + k);
        const col = part.every(t => t.k === "w" || t.k === "q") ?
          byName.get(norm(part.map(t => t.t).join(" "))) : undefined;
        if (col !== undefined) return [col, i + k];
      }
    };
    const opAt = j => {
      const hit = PHRASES.find(([ws]) => ws.every((w, k) => /^[wo]$/.test(toks[j + k]?.k) && lower(toks[j + k]) === w));
      return hit && { op: hit[1], n: hit[0].length };
    };
    const val = j => toks[j]?.k === "w" || toks[j]?.k === "q" ? toks[j].t : null;
    // a bare value after a column name (`color red`): not an operator or joiner
    const bare = j => val(j) != null && !opAt(j) && !["and", "or"].includes(lower(toks[j]));
    // condition at token j -> [term, next token], or undefined
    const cond = j => {
      const o = opAt(j);
      if (!o) return;
      const i = j + o.n, a = val(i);
      if (a == null) return;
      if (o.op === "between") {
        const b = lower(toks[i + 1]) === "and" ? val(i + 2) : null;
        if (b != null && isNum(a) && isNum(b)) return [`x >= ${num(a)} && x <= ${num(b)}`, i + 3];
      } else if (o.op === ":") return [a, i + 1];
      else if (o.op === "==" || o.op === "!=") {
        if (isNum(a)) return [`x ${o.op} ${num(a)}`, i + 1];
        // text compares ignoring case; the summary shows the plain `x == "A"`
        return [`String(x).toLowerCase() ${o.op} ${JSON.stringify(a.toLowerCase())}`, i + 1, `x ${o.op} ${JSON.stringify(a)}`];
      }
      else if (isNum(a)) return [`x ${o.op} ${num(a)}`, i + 1];
    };

    const alts = [[]];          // `or` alternatives, each a list of ANDed leaves
    let last = null, lastEnd = -1;  // free-text leaf being extended, and its end
    const add = leaf => { alts.at(-1).push(leaf); last = null; };
    for (let i = 0; i < toks.length;) {
      const t = toks[i];
      if (t.k === "s") { last = null; i++; continue; }
      if (t.k === "w" && lower(t) === "or" && alts.at(-1).length) {
        alts.push([]); last = null; i++; continue;
      }
      let col, hit, n = named(i);
      if (n && (hit = cond(n[1]) || (bare(n[1]) && [val(n[1]), n[1] + 1]))) col = n[0];
      else if (col0 != null && (hit = cond(i))) col = col0;
      if (hit) {
        add({ col, term: hit[0], show: hit[2] });
        i = hit[1];
        if (lower(toks[i]) === "and") i++;  // `a and b`
        continue;
      }
      // free text; pieces with no space between rejoin (`foo:bar`, `a>b`)
      if (last && lastEnd === t.s) last.term += t.t;
      else { last = { col: col0, term: t.t, free: true }; alts.at(-1).push(last); }
      lastEnd = t.e;
      i++;
    }
    const ands = alts.filter(a => a.length).map(a => a.length > 1 ? { op: "and", items: a } : a[0]);
    return ands.length > 1 ? { op: "or", items: ands } : ands[0] ?? null;
  }

  // One-line reading of a tree, e.g. `Price: x > 20 and "foo"`. `label(col)` names a
  // column; a null label omits the prefix.
  function text(tree, label = c => c) {
    if (!tree) return "";
    if (!tree.op) {
      const name = tree.col != null && label(tree.col);
      return (name ? `${name}: ` : "") + (isExpr(tree.term) ? tree.show ?? tree.term : `"${tree.term}"`);
    }
    // a group of the other operator reads better in parentheses
    const part = n => n.op && n.op !== tree.op ? `(${text(n, label)})` : text(n, label);
    return tree.items.map(part).join(tree.op === "and" ? " and " : " or ");
  }

  // Did the parser read anything beyond plain text (a condition, or `or`)?
  const parsed = t => !!t && (t.op === "or" || (t.op ? t.items.some(parsed) : !t.free));

  // The tree as one expression on `x`, or null if any part is plain text (for a
  // single column's box, which holds one expression).
  function expr(tree) {
    if (!tree) return null;
    if (!tree.op) return isExpr(tree.term) ? tree.term : null;
    const parts = tree.items.map(expr);
    return parts.includes(null) ? null :
      parts.map(p => `(${p})`).join(tree.op === "and" ? " && " : " || ");
  }

  const Q = { parse, text, expr, parsed, isExpr };
  if (typeof module === "object" && module.exports) module.exports = Q;
  else ((root.LT ||= {}).plugins ||= {}).query = Q;
})(typeof window !== "undefined" ? window : globalThis);
