/* lt-export.js — table export formats (CSV, RTF) for lt.
 *
 * Plugin on the LT global (see lt.js), loaded after core. No DOM: each format
 * turns a plain model of the table into a string, so the same code serves the
 * download button of lt-interactive.js and Node (`lt_export()` in R). Add a
 * format by adding an entry to `formats`; the download menu lists them all.
 *
 *   LT.plugins.export.text(format, spec, rows?, src?)
 *
 * `spec` is a built spec (after LT.buildHtml), `rows` 1-based row indices
 * (default: all), `src` the cell text by column (default: displayed text).
 */
(root => {
  "use strict";
  const LT = root.LT;
  if (!LT?.plugins || LT.plugins.export) return;

  // Text fields are a plain string or, if wrapped in I() in R, a one-element
  // array of raw HTML (tags dropped).
  const plain = v => Array.isArray(v) ? String(v[0] ?? "").replace(/<[^>]*>/g, "") : String(v ?? "");

  // CSV: quote (doubling quotes) only if comma, quote, or newline.
  const csvField = v => /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v;
  const csv = m => [m.head, ...m.rows].map(r => r.map(csvField).join(",")).join("\n");

  // RTF: escape \ { }, line breaks, and non-ASCII (as signed 16-bit \u codes).
  const rtfEsc = v => v.replace(/[\\{}]/g, "\\$&").replace(/\r?\n/g, "\\line ")
    .replace(/[^\x00-\x7f]/g, c => `\\u${(c.charCodeAt(0) << 16) >> 16}?`);
  // A fixed look: rules above and below the header and below the last row, bold
  // header, spanners as merged cells, title above and notes below, column
  // widths by text length.
  const rtf = ({ head, rows, align, indent, spans, title, subtitle, notes }) => {
    const W = 9360,  // text width in twips (6.5in)
          len = head.map((h, j) => Math.min(30, rows.reduce((n, r) => Math.max(n, r[j].length), Math.max(4, h.length)))),
          tot = len.reduce((a, b) => a + b, 0);
    let x = 0;
    const edge = len.map(l => x += Math.round(l / tot * W)),
          // cells: [text, {a: align, b: bold, li: indent, bd: border sides, m: merge}]
          row = cells => "\\trowd\\trgaph60" + cells.map(([, o], j) =>
            (o.m || "") + [...(o.bd || "")].map(s => `\\clbrdr${s}\\brdrs\\brdrw10`).join("") + `\\cellx${edge[j]}`
          ).join("") + cells.map(([t, o]) =>
            `\\pard\\intbl\\q${o.a || "l"}${o.li ? `\\li${o.li}` : ""} ${o.b ? `{\\b ${rtfEsc(t)}}` : rtfEsc(t)}\\cell`
          ).join("") + "\\row\n",
          out = ["{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Arial;}}\\fs18\n"];
    if (title) out.push(`{\\pard\\qc\\b ${rtfEsc(title)}\\par}\n`);
    if (subtitle) out.push(`{\\pard\\qc ${rtfEsc(subtitle)}\\par}\n`);
    if (spans.length) {
      const cells = [];
      for (let j = 0; j < head.length;) {
        const s = spans.find(s => s.from === j);
        if (!s) { cells.push(["", { bd: "t" }]); j++; continue; }
        cells.push([s.label, { a: "c", bd: "tb", m: "\\clmgf" }]);
        for (let k = 1; k < s.n; k++) cells.push(["", { bd: "tb", m: "\\clmrg" }]);
        j += s.n;
      }
      out.push(row(cells));
    }
    out.push(row(head.map((h, j) => [h, { a: align[j], b: 1, bd: (spans.length ? "" : "t") + "b" }])));
    rows.forEach((r, i) => out.push(row(r.map((t, j) => [t, {
      a: align[j], li: j ? 0 : indent[i] * 240, bd: i === rows.length - 1 ? "b" : ""
    }]))));
    for (const n of notes) out.push(`{\\pard\\fs16 ${rtfEsc(n)}\\par}\n`);
    return out.join("") + "}";
  };

  // Registered formats: key (also the file extension) -> label, MIME type, and
  // `fn(model)`.
  const formats = {
    csv: { label: "CSV", mime: "text/csv", fn: csv },
    rtf: { label: "RTF", mime: "application/rtf", fn: rtf },
  };

  // The table as plain strings: header, body rows, and what a format may use
  // beyond them (alignment, row indents, spanners as column ranges, title,
  // notes).
  const model = (spec, rows, src = spec._display) => {
    const cols = spec._cols, t = spec._tbl, ind = spec._indent;
    rows ||= Array.from({ length: src[cols[0]]?.length ?? 0 }, (_, i) => i + 1);
    return {
      head: t.labels.map(plain),
      rows: rows.map(r => cols.map(c => String(src[c]?.[r - 1] ?? ""))),
      align: t.align.map(a => ({ center: "c", right: "r" })[a] || "l"),
      indent: rows.map(r => ind?.[r - 1] || 0),
      spans: (t.spanners || []).map(s => ({
        label: plain(s.label), from: cols.indexOf(s.columns[0]), n: s.columns.length
      })),
      title: plain(t.header.title), subtitle: plain(t.header.subtitle),
      notes: (t.notes || []).map(plain)
    };
  };

  LT.plugins.export = {
    formats, model,
    text: (fmt, spec, rows, src) => formats[fmt].fn(model(spec, rows, src))
  };
})(window);
