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

  // --- Number formatting ---
  function fmtNumber(v, decimals, bigMark) {
    if (v == null || typeof v !== "number" || isNaN(v)) return null;
    let s = v.toFixed(decimals);
    if (bigMark) {
      const parts = s.split(".");
      parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, bigMark);
      s = parts.join(".");
    }
    return s;
  }

  // --- Pattern merge ---
  function mergeVals(vals, pattern) {
    if (!pattern) return vals.filter(v => v !== "").join(" ");
    let remaining = pattern, result = "";
    while (remaining) {
      const m = remaining.match(/<<(.*?)>>/);
      if (!m) { result += subRefs(remaining, vals); break; }
      if (m.index > 0) result += subRefs(remaining.slice(0, m.index), vals);
      const block = m[1];
      const refs = [...block.matchAll(/\{(\d+)\}/g)].map(x => +x[1]);
      if (!refs.length || refs.every(i => vals[i - 1] !== ""))
        result += subRefs(block, vals);
      remaining = remaining.slice(m.index + m[0].length);
    }
    return result;
  }
  function subRefs(s, vals) {
    for (let i = 0; i < vals.length; i++)
      s = s.split("{" + (i + 1) + "}").join(vals[i]);
    return s;
  }

  // --- Apply ops to data columns, return display strings per column ---
  function applyOps(spec) {
    const data = spec.data || {},
          ops = spec.ops || [],
          colNames = Object.keys(data),
          nRow = colNames.length ? data[colNames[0]].length : 0;

    // Working copy: display[col][row] = string
    const display = {};
    for (const c of colNames) {
      display[c] = data[c].map(v => v == null ? "" : String(v));
    }

    for (const op of ops) {
      const cols = op.columns || colNames;
      switch (op.type) {
        case "fmt_number":
          for (const c of cols) {
            if (!data[c]) continue;
            for (let i = 0; i < nRow; i++) {
              const raw = data[c][i];
              const f = fmtNumber(raw, op.decimals ?? 2, op.big_mark ?? "");
              if (f != null) display[c][i] = f;
            }
          }
          break;
        case "sub":
          for (const c of cols) {
            if (!data[c]) continue;
            for (let i = 0; i < nRow; i++) {
              const raw = data[c][i];
              if (op.small != null && typeof raw === "number" && raw !== 0 &&
                  !isNaN(raw) && raw != null && Math.abs(raw) < op.small) {
                display[c][i] = op.small_text ?? ("<" + op.small);
              } else if (op.zero != null && raw === 0) {
                display[c][i] = op.zero;
              } else if (op.missing != null && raw == null) {
                display[c][i] = op.missing;
              }
            }
          }
          break;
        case "merge": {
          const mCols = op.columns;
          if (!mCols || mCols.length < 2) break;
          const target = mCols[0];
          for (let i = 0; i < nRow; i++) {
            const vals = mCols.map(c => display[c] ? display[c][i] : "");
            display[target][i] = mergeVals(vals, op.pattern);
          }
          break;
        }
      }
    }
    return { display, nRow };
  }

  // --- Resolve structural spec fields from ops + data ---
  function resolveSpec(spec) {
    const data = spec.data || {},
          ops = spec.ops || [],
          colNames = Object.keys(data),
          nRow = colNames.length ? data[colNames[0]].length : 0;

    // Determine row_group and row_label columns
    const rowGroupCol = spec.row_group || null,
          rowLabelCol = spec.row_label || null;

    // Hidden columns: row_group, row_label, merge sources
    const hidden = new Set();
    if (rowGroupCol) hidden.add(rowGroupCol);
    if (rowLabelCol) hidden.add(rowLabelCol);
    for (const op of ops) {
      if (op.type === "merge" && op.hide !== false && op.columns)
        op.columns.slice(1).forEach(c => hidden.add(c));
    }

    // Visible columns after hiding
    let visible = colNames.filter(c => !hidden.has(c));

    // Apply cols_move
    for (const op of ops) {
      if (op.type !== "cols_move") continue;
      const toMove = (op.columns || []).filter(c => visible.includes(c));
      if (!toMove.length) continue;
      const rest = visible.filter(c => !toMove.includes(c));
      if (op.after == null) {
        visible = [...toMove, ...rest];
      } else {
        const pos = rest.indexOf(op.after);
        if (pos >= 0) visible = [...rest.slice(0, pos + 1), ...toMove, ...rest.slice(pos + 1)];
      }
    }

    // Alignment: default from data type (number→right, else left), then overrides
    const align = visible.map(c => {
      const col = data[c];
      return col && col.length && typeof col.find(v => v != null) === "number" ? "right" : "left";
    });
    for (const op of ops) {
      if (op.type !== "align") continue;
      for (const c of (op.columns || [])) {
        const i = visible.indexOf(c);
        if (i >= 0) align[i] = op.align;
      }
    }

    // Column labels
    const colLabels = [...visible];
    for (const op of ops) {
      if (op.type !== "cols_label" || !op.labels) continue;
      for (const [c, lbl] of Object.entries(op.labels)) {
        const i = visible.indexOf(c);
        if (i >= 0) colLabels[i] = lbl;
      }
    }

    // Column widths
    let colWidths = null;
    for (const op of ops) {
      if (op.type !== "cols_width" || !op.widths) continue;
      if (!colWidths) colWidths = visible.map(() => "");
      for (const [c, w] of Object.entries(op.widths)) {
        const i = visible.indexOf(c);
        if (i >= 0) colWidths[i] = w;
      }
    }

    // Indent
    const indent = new Array(nRow).fill(0);
    for (const op of ops) {
      if (op.type !== "indent" || !op.rows) continue;
      for (const r of op.rows) indent[r - 1] = op.level ?? 1;
    }

    // Stubhead
    let stubLabel = rowLabelCol || "";
    for (const op of ops) {
      if (op.type === "stubhead") stubLabel = op.label;
    }

    // Row groups from data column
    let groups = [];
    if (rowGroupCol && data[rowGroupCol]) {
      const gCol = data[rowGroupCol];
      let i = 0;
      while (i < nRow) {
        const label = gCol[i] == null ? "" : String(gCol[i]);
        const rows = [i + 1];
        while (++i < nRow && String(gCol[i] ?? "") === label) rows.push(i + 1);
        groups.push({ label, rows });
      }
    }
    // Manual groups
    for (const op of ops) {
      if (op.type === "row_group") groups.push({ label: op.label, rows: op.rows });
    }
    // Group ordering
    for (const op of ops) {
      if (op.type !== "group_order" || !groups.length) continue;
      const order = op.order || [];
      const ordered = [], rest = [];
      for (const lbl of order) {
        const g = groups.find(x => x.label === lbl);
        if (g) ordered.push(g);
      }
      for (const g of groups) if (!ordered.includes(g)) rest.push(g);
      groups = [...ordered, ...rest];
    }

    // Styles
    const styles = [];
    for (const op of ops) {
      if (op.type !== "style") continue;
      const s = { css: op.css };
      if (op.columns) s.columns = op.columns;
      if (op.rows) s.rows = op.rows;
      styles.push(s);
    }

    // Stub values from row_label column
    const stub = rowLabelCol && data[rowLabelCol]
      ? data[rowLabelCol].map(v => v == null ? "" : String(v))
      : null;

    return {
      visible, align, colLabels, colWidths, indent, stubLabel, stub,
      groups, styles,
      spanners: spec.spanners || [],
      footnotes: spec.footnotes || [],
      notes: spec.notes || [],
      header: spec.header || {},
      nRow
    };
  }

  // Footnotes: dedup by text, assign 1..N in first-seen order.
  function indexFootnotes(fns) {
    const order = [], idx = {};
    fns.forEach(f => {
      if (idx[f.text] == null) { idx[f.text] = order.length + 1; order.push(f.text); }
    });
    return { order, idx };
  }

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
    const { display, nRow } = applyOps(spec);
    const res = resolveSpec(spec);
    const { visible: cols, align, colLabels, colWidths, indent, stubLabel,
            stub, groups, styles, spanners, footnotes: fns, notes, header: hdr } = res;
    const reg = indexFootnotes(fns),
          fIdx = matcher(fns, reg.idx),
          nCol = cols.length + (stub ? 1 : 0),
          out = [`<table class="lt-table">`];
    const alCls = i => { const a = align[i]; return a === "right" ? " class=\"al-r\"" : a === "center" ? " class=\"al-c\"" : ""; };
    const mark = (type, p) => { const i = fIdx(type, p); return i ? sup(i) : ""; };

    // Style map
    const styleMap = {};
    for (const s of styles) {
      const sCols = s.columns || cols, sRows = s.rows;
      for (let r = 1; r <= nRow; r++) {
        if (sRows && sRows.indexOf(r) < 0) continue;
        for (const c of sCols) {
          const ci = cols.indexOf(c);
          if (ci < 0) continue;
          const key = `${r},${ci}`;
          styleMap[key] = styleMap[key] ? styleMap[key] + ";" + s.css : s.css;
        }
      }
    }

    // <colgroup>
    if (colWidths && colWidths.some(w => w)) {
      out.push(`<colgroup>`);
      if (stub) out.push(`<col>`);
      for (let i = 0; i < cols.length; i++)
        out.push(colWidths[i] ? `<col style="width:${colWidths[i]}">` : `<col>`);
      out.push(`</colgroup>`);
    }

    // <caption>
    const hasT = hdr.title != null && hdr.title !== "",
          hasS = hdr.subtitle != null && hdr.subtitle !== "";
    if (hasT || hasS) {
      out.push(`<caption class="lt-caption">`);
      if (hasT) out.push(`<div class="lt-title">${esc(hdr.title)}${mark("title", { group: "title" })}</div>`);
      if (hasS) out.push(`<div class="lt-subtitle">${esc(hdr.subtitle)}${mark("title", { group: "subtitle" })}</div>`);
      out.push(`</caption>`);
    }

    // <thead>
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

    // Body footnote markers
    const bodyMarks = {};
    for (const f of fns) {
      if (f.location.type !== "body") continue;
      const fi = reg.idx[f.text],
            fcols = f.location.columns || [],
            frows = f.location.rows;
      for (let r = 1; r <= nRow; r++) {
        if (frows && frows.indexOf(r) < 0) continue;
        for (const c of fcols) {
          const ci = cols.indexOf(c);
          if (ci >= 0) bodyMarks[`${r},${ci}`] = fi;
        }
      }
    }

    // Row rendering
    const pushRow = r => {
      out.push(`<tr>`);
      if (stub) {
        const ind = indent[r - 1] || 0;
        const style = ind ? ` style="padding-left:${ind + 1}em"` : "";
        out.push(`<th scope="row" class="lt-stub"${style}>${esc(stub[r - 1])}</th>`);
      }
      for (let ci = 0; ci < cols.length; ci++) {
        const m = bodyMarks[`${r},${ci}`];
        const s = styleMap[`${r},${ci}`];
        const val = display[cols[ci]] ? display[cols[ci]][r - 1] : "";
        out.push(`<td${alCls(ci)}${s ? ` style="${s}"` : ""}>${esc(val)}${m ? sup(m) : ""}</td>`);
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
      for (let r = 1; r <= nRow; r++) if (!seen[r]) pushRow(r);
    } else {
      for (let r = 1; r <= nRow; r++) pushRow(r);
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

  const q = root.LT && root.LT.q || [];
  while (q.length) { const e = q.shift(); mount(e.s, e.d); }
  root.LT = { build(spec) { mount(document.currentScript, spec); }, buildHtml,
    q: { push(e) { mount(e.s, e.d); } } };
})(window);
