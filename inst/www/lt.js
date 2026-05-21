/* lt.js — build a semantic <table> from a JSON spec.
 * Call LT.build(spec) from an inline <script> to render a table in place.
 * One runtime per page renders any number of tables.
 */
(root => {
  "use strict";
  if (root.LT && root.LT.buildHtml) return;  // duplicate inclusion is a no-op

  // `[<]` (not `<`) avoids `</…` so this file is safe to inline in <script>.
  const esc = s => String(s)
    .replace(/&/g, "&amp;").replace(/[<]/g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const sup = i => `<sup class="lt-fnref">${i}</sup>`;

  // Footnotes: dedup by text, assign 1..N in first-seen order.
  function indexFootnotes(fns) {
    const order = [], idx = {};
    fns.forEach(f => {
      if (idx[f.text] == null) { idx[f.text] = order.length + 1; order.push(f.text); }
    });
    return { order, idx };
  }

  // matcher(fns, idx)(type, p) → 1-based footnote index whose location
  // matches, or 0. Encapsulates all "what footnote applies here?" logic.
  const matcher = (fns, idx) => (type, p) => {
    for (const f of fns) {
      const loc = f.location;
      if (loc.type !== type) continue;
      const hit = idx[f.text];
      if (type === "title" && loc.group === p.group) return hit;
      if (type === "column_labels" &&
          p.columns.every(c => loc.columns.indexOf(c) >= 0)) return hit;
      if (type === "column_spanners" &&
          p.spanners.every(s => loc.spanners.indexOf(s) >= 0)) return hit;
      if (type === "row_groups") {
        if (loc.match === "all") return hit;
        if (loc.match === "exact" && loc.values.indexOf(p.label) >= 0) return hit;
        if (loc.match === "starts_with" && p.label.indexOf(loc.value) === 0) return hit;
      }
    }
    return 0;
  };

  function buildHtml(spec) {
    const cols = spec.columns || [],
          colLabels = spec.col_labels || cols,
          align = spec.align || [],
          rows = spec.rows || [],
          stub = spec.stub,
          spanners = spec.spanners || [],
          groups = spec.row_groups || [],
          fns = spec.footnotes || [],
          notes = spec.notes || [],
          hdr = spec.header || {},
          reg = indexFootnotes(fns),
          fIdx = matcher(fns, reg.idx),
          stubLabel = spec.stub_label || "",
          nCol = cols.length + (stub ? 1 : 0),
          out = [`<table class="lt-table table">`];
    const alCls = i => { const a = align[i]; return a === "right" ? " class=\"al-r\"" : a === "center" ? " class=\"al-c\"" : ""; };
    const mark = (type, p) => { const i = fIdx(type, p); return i ? sup(i) : ""; };

    // <caption>
    const hasT = hdr.title != null && hdr.title !== "",
          hasS = hdr.subtitle != null && hdr.subtitle !== "";
    if (hasT || hasS) {
      out.push(`<caption class="lt-caption">`);
      if (hasT) out.push(`<div class="lt-title">${esc(hdr.title)}${mark("title", { group: "title" })}</div>`);
      if (hasS) out.push(`<div class="lt-subtitle">${esc(hdr.subtitle)}${mark("title", { group: "subtitle" })}</div>`);
      out.push(`</caption>`);
    }

    // <thead>: optional spanner row + column-label row.
    out.push(`<thead>`);
    if (spanners.length) {
      out.push(`<tr class="lt-spanner-row">${stub ? `<th class="lt-spanner-empty"></th>` : ""}`);
      for (let k = 0; k < cols.length;) {
        const sp = spanners.find(s => s.columns[0] === cols[k]);
        if (sp) {
          out.push(`<th colspan="${sp.columns.length}" scope="colgroup" class="lt-spanner">${esc(sp.label)}${mark("column_spanners", { spanners: [sp.label] })}</th>`);
          k += sp.columns.length;
        } else {
          out.push(`<th class="lt-spanner-empty"></th>`);
          k++;
        }
      }
      out.push(`</tr>`);
    }
    out.push(`<tr>${stub ? `<th scope="col">${esc(stubLabel)}</th>` : ""}`);
    for (let i = 0; i < cols.length; i++)
      out.push(`<th scope="col"${alCls(i)}>${esc(colLabels[i])}${mark("column_labels", { columns: [cols[i]] })}</th>`);
    out.push(`</tr></thead>`);

    // body-footnote markers per (row,col), 1-based row.
    const bodyMarks = {};
    for (const f of fns) {
      if (f.location.type !== "body") continue;
      const fi = reg.idx[f.text],
            fcols = f.location.columns || [],
            frows = f.location.rows;  // absent = all
      for (let r = 1; r <= rows.length; r++) {
        if (frows && frows.indexOf(r) < 0) continue;
        for (const c of fcols) {
          const ci = cols.indexOf(c);
          if (ci >= 0) bodyMarks[`${r},${ci}`] = fi;
        }
      }
    }

    const pushRow = r => {
      out.push(`<tr>`);
      if (stub) out.push(`<th scope="row" class="lt-stub">${esc(stub[r - 1])}</th>`);
      for (let ci = 0; ci < cols.length; ci++) {
        const m = bodyMarks[`${r},${ci}`];
        out.push(`<td${alCls(ci)}>${esc(rows[r - 1][ci])}${m ? sup(m) : ""}</td>`);
      }
      out.push(`</tr>`);
    };

    // <tbody>
    out.push(`<tbody>`);
    if (groups.length) {
      const seen = {};
      for (const g of groups) {
        out.push(`<tr class="lt-row-group"><th colspan="${nCol}" scope="colgroup">${esc(g.label)}${mark("row_groups", { label: g.label })}</th></tr>`);
        for (const r of g.rows) { seen[r] = 1; pushRow(r); }
      }
      for (let r = 1; r <= rows.length; r++) if (!seen[r]) pushRow(r);
    } else {
      for (let r = 1; r <= rows.length; r++) pushRow(r);
    }
    out.push(`</tbody>`);

    // <tfoot>
    if (reg.order.length || notes.length) {
      out.push(`<tfoot class="lt-footer">`);
      reg.order.forEach((txt, i) => out.push(
        `<tr class="lt-footnote"><td colspan="${nCol}">${sup(i + 1)} ${esc(txt)}</td></tr>`));
      for (const n of notes)
        out.push(`<tr class="lt-source-note"><td colspan="${nCol}">${esc(n)}</td></tr>`);
      out.push(`</tfoot>`);
    }

    out.push(`</table>`);
    return out.join("");
  }

  const mount = (s, spec) => s.insertAdjacentHTML("afterend", buildHtml(spec));

  (root.LT && root.LT.q || []).forEach(e => mount(e.s, e.d));
  root.LT = { build(spec) { mount(document.currentScript, spec); }, buildHtml };
})(window);
