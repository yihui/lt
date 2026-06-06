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
  const isNum = v => typeof v === "number" && !isNaN(v);

  function fmtNumber(v, decimals, bigMark) {
    if (v == null || !isNum(v)) return null;
    let s = decimals != null ? v.toFixed(decimals) : String(v);
    if (/^-0(\.0+)?$/.test(s)) s = s.slice(1);
    if (bigMark) {
      const parts = s.split(".");
      parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, bigMark);
      s = parts.join(".");
    }
    if (s[0] === "-") s = "−" + s.slice(1);
    return decimals != null || bigMark ? s : null;
  }

  // --- Pattern merge ---
  function mergeVals(vals, pattern) {
    if (!pattern) return vals.filter(v => v !== "").join(" ");
    let remaining = pattern, result = "";
    while (remaining) {
      const m = remaining.match(/<<(.*?)>>/);
      if (!m) { result += subRefs(remaining, vals); break; }
      if (m.index > 0) result += subRefs(remaining.slice(0, m.index), vals);
      const block = m[1],
            refs = [...block.matchAll(/\{(\d+)\}/g)].map(x => +x[1]);
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

  // --- Auto-format numeric columns ---
  function autoFmt(spec, display, nRow) {
    if (spec.auto_fmt === false) return;
    const data = spec.data || {}, ops = spec.ops || [],
          colNames = Object.keys(data);

    const fmtCols = new Set();
    for (const op of ops) {
      if (op.type === "fmt_number") for (const c of (op.columns || colNames)) fmtCols.add(c);
    }

    const getLabel = c => {
      for (const op of ops) {
        if (op.type === "label" && op.labels && op.labels[c] != null) return op.labels[c];
      }
      return c;
    };

    for (const c of colNames) {
      if (fmtCols.has(c)) continue;
      const col = data[c];
      if (!col || !col.length) continue;
      if (typeof col.find(v => v != null) !== "number") continue;

      const lbl = getLabel(c),
            pct = /%|[ _](pct|percent)$/i.test(lbl);

      if (/year/i.test(lbl) && col.every(v => v == null || /^\d{4}$/.test(String(v)))) continue;

      // Determine decimal places: find max significant decimals across column,
      // then cap dynamically based on the largest integer-part width (targeting
      // ~4 total significant digits): e.g., values <1 get up to 4 decimals,
      // 10-99 get 2, >=1000 get 0.
      let maxInt = 0, n = 0;
      for (const v of col) {
        if (!isNum(v)) continue;
        // Number of digits before the decimal point
        const a = Math.abs(pct ? v * 100 : v),
              intW = a < 1 ? 0 : Math.floor(Math.log10(a)) + 1;
        if (intW > maxInt) maxInt = intW;
        // Significant decimals (strip trailing zeros; adjust for pct *100)
        const m = String(v).match(/\.(\d+)/);
        if (!m) continue;
        const d = m[1].replace(/0+$/, "").length - (pct ? 2 : 0);
        if (d > n) n = d;
      }
      // Cap: 4 decimals max, minus integer width (so large numbers get fewer)
      n = Math.max(Math.min(n, Math.max(4 - maxInt, 0)), 0);

      for (let i = 0; i < nRow; i++) {
        const v = col[i];
        if (!isNum(v)) continue;
        const s = fmtNumber(pct ? v * 100 : v, n, " ");
        if (s != null) display[c][i] = s + (pct ? "%" : "");
      }
    }
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

    autoFmt(spec, display, nRow);

    for (const op of ops) {
      const cols = op.columns || colNames;
      switch (op.type) {
        case "fmt_number":
          for (const c of cols) {
            if (!data[c]) continue;
            for (let i = 0; i < nRow; i++) {
              const raw = data[c][i];
              if (raw == null || !isNum(raw)) continue;
              const v = op.percent === true ? raw * 100 : raw,
                    sfx = op.percent ? "%" : "",
                    f = fmtNumber(v, op.decimals, op.big_mark ?? "");
              if (f != null) display[c][i] = f + sfx;
              else if (sfx) display[c][i] = String(v) + sfx;
            }
          }
          break;
        case "sub":
          for (const c of cols) {
            if (!data[c]) continue;
            for (let i = 0; i < nRow; i++) {
              const raw = data[c][i];
              if (op.small != null && isNum(raw) && raw !== 0 &&
                  Math.abs(raw) < op.small) {
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

    // row_group: array → rowspan mode; string → separator-row mode
    let rowGroupSep = typeof spec.row_group === "string";
    const rowGroupCols = Array.isArray(spec.row_group) ? spec.row_group
          : (spec.row_group ? [spec.row_group] : []),
          rowLabelCol = spec.row_label || null;
    if (!rowGroupSep && rowGroupCols.length === 1 &&
        data[rowGroupCols[0]]?.some(v => (v + "").length > 20)) rowGroupSep = true;

    // Hidden columns: row_group, row_label, merge sources
    const hidden = new Set();
    for (const g of rowGroupCols) hidden.add(g);
    if (rowLabelCol) hidden.add(rowLabelCol);
    for (const op of ops) {
      if (op.type === "merge" && op.hide !== false && op.columns)
        op.columns.slice(1).forEach(c => hidden.add(c));
    }

    // Visible columns after hiding
    let visible = colNames.filter(c => !hidden.has(c));

    // Apply move
    for (const op of ops) {
      if (op.type !== "move") continue;
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
      if (op.type !== "label" || !op.labels) continue;
      for (const [c, lbl] of Object.entries(op.labels)) {
        const i = visible.indexOf(c);
        if (i >= 0) colLabels[i] = lbl;
      }
    }

    // Column widths
    let colWidths = null;
    for (const op of ops) {
      if (op.type !== "width" || !op.widths) continue;
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
    let stubLabel = "";
    for (const op of ops) {
      if (op.type === "stubhead") stubLabel = op.label;
    }

    // Row groups from data column (separator-row mode only)
    let groups = [];
    if (rowGroupSep && rowGroupCols.length && data[rowGroupCols[0]]) {
      const gCol = data[rowGroupCols[0]];
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

    // Rowspan groups: compute span sizes for each group column
    const rowSpans = [];
    if (!rowGroupSep && rowGroupCols.length) {
      for (const gc of rowGroupCols) {
        const col = data[gc] || [], spans = new Array(nRow).fill(0);
        let i = 0;
        while (i < nRow) {
          const label = String(col[i] ?? "");
          let j = i + 1;
          while (j < nRow && String(col[j] ?? "") === label) j++;
          spans[i] = j - i;
          i = j;
        }
        // Resolve display label from label ops
        let hdr = gc;
        for (const op of ops) {
          if (op.type === "label" && op.labels && op.labels[gc] != null) hdr = op.labels[gc];
        }
        rowSpans.push({ col: gc, label: hdr, spans });
      }
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

    // Stub: explicit row_label, or auto-promote first visible non-numeric column when groups exist
    const autoStub = groups.length && !rowLabelCol && visible.length
      ? visible.find(c => !data[c] || !data[c].length || typeof data[c].find(v => v != null) !== "number")
      : null;
    const stubCol = rowLabelCol || autoStub || null;
    const stub = stubCol && data[stubCol]
      ? data[stubCol].map(v => v == null ? "" : String(v))
      : null;
    if (stubCol && !rowLabelCol) {
      align.shift(); colLabels.shift(); visible = visible.slice(1);
      if (colWidths) colWidths.shift();
    }
    if (stubCol && !stubLabel) stubLabel = stubCol;

    // Auto-spanners: split column names on separator, group contiguous prefixes
    let spanners = spec.spanners || [];
    if (spec.auto_span) {
      const sep = typeof spec.auto_span === "string" ? new RegExp(spec.auto_span) : /[._]/;
      spanners = [...spanners];
      for (let i = 0; i < visible.length;) {
        const m = visible[i].match(sep);
        if (!m) { i++; continue; }
        const prefix = visible[i].slice(0, m.index);
        let j = i + 1;
        while (j < visible.length) {
          const m2 = visible[j].match(sep);
          if (!m2 || visible[j].slice(0, m2.index) !== prefix) break;
          j++;
        }
        if (j - i >= 2) {
          spanners.push({ label: prefix, columns: visible.slice(i, j) });
          for (let k = i; k < j; k++) {
            const mk = colLabels[k].match(sep);
            if (mk) colLabels[k] = colLabels[k].slice(mk.index + mk[0].length);
          }
        }
        i = j;
      }
    }

    return {
      visible, align, colLabels, colWidths, indent, stubLabel, stub,
      groups, rowSpans, styles, spanners,
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
    const { display, nRow } = applyOps(spec),
          { visible: cols, align, colLabels, colWidths, indent, stubLabel,
            stub, groups, rowSpans, styles, spanners, footnotes: fns, notes, header: hdr } = resolveSpec(spec),
          reg = indexFootnotes(fns),
          fIdx = matcher(fns, reg.idx),
          nGrp = rowSpans.length,
          nCol = cols.length + (stub ? 1 : 0) + nGrp,
          out = [`<table class="lt-table">`];
    const mark = (type, p) => { const i = fIdx(type, p); return i ? sup(i) : ""; };
    const colCls = cols.map((_, i) => {
      const c = (!stub && i === 0 && groups.length ? "lt-indent " : "") +
        ({right: "al-r", center: "al-c"}[align[i]] || "");
      return c ? ` class="${c.trimEnd()}"` : "";
    });

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
      out.push(`<tr class="lt-spanner-row">`);
      for (let k = 0; k < nGrp; k++) out.push(`<th class="lt-spanner-empty"></th>`);
      if (stub) out.push(`<th class="lt-spanner-empty"></th>`);
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
    out.push(`<tr>`);
    for (const rs of rowSpans) out.push(`<th scope="col">${esc(rs.label)}</th>`);
    if (stub) out.push(`<th scope="col"${groups.length ? ` class="lt-indent"` : ""}>${esc(stubLabel)}</th>`);
    for (let i = 0; i < cols.length; i++)
      out.push(`<th scope="col"${colCls[i]}>${esc(colLabels[i])}${mark("column_labels", { columns: [cols[i]] })}</th>`);
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
      // Rowspan group cells
      for (const rs of rowSpans) {
        const span = rs.spans[r - 1];
        if (span > 0) out.push(`<th scope="row" class="lt-row-group"${span > 1 ? ` rowspan="${span}"` : ""}>${esc(display[rs.col] ? display[rs.col][r - 1] : "")}</th>`);
      }
      if (stub) {
        const ind = indent[r - 1] || 0,
              cls = `lt-stub${groups.length ? " lt-indent" : ""}`,
              style = ind ? ` style="padding-left:${ind + 1}em"` : "";
        out.push(`<th scope="row" class="${cls}"${style}>${esc(stub[r - 1])}</th>`);
      }
      for (let ci = 0; ci < cols.length; ci++) {
        const m = bodyMarks[`${r},${ci}`],
              s = styleMap[`${r},${ci}`],
              val = display[cols[ci]] ? display[cols[ci]][r - 1] : "";
        out.push(`<td${colCls[ci]}${s ? ` style="${s}"` : ""}>${esc(val)}${m ? sup(m) : ""}</td>`);
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
