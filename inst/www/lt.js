/* lt.js — build a semantic <table> from a JSON spec.
 * Call LT.build(spec) from an inline <script> to render a table in place.
 * One runtime per page renders any number of tables.
 */
(root => {
  "use strict";
  if (root.LT?.buildHtml) return;  // duplicate inclusion is a no-op

  // `[<]` (not `<`) avoids `</…` so this file is safe to inline in <script>.
  const esc = s => String(s)
    .replace(/&/g, "&amp;").replace(/[<]/g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  // Text fields (title, labels, footnotes, ...) arrive as a plain string
  // (escape it) or, when the R side wrapped them in I(), a one-element array
  // (emit verbatim as raw HTML). `txt` renders either form.
  const txt = v => Array.isArray(v) ? String(v[0] ?? "") : esc(v);
  // Raw (verbatim) if `raw`, else escaped — for values already stringified
  // (e.g. body cells whose column is flagged raw via spec.html_cols).
  const escIf = (raw, s) => raw ? String(s ?? "") : esc(s);
  // Is column `c` flagged raw HTML? `hc` is spec.html_cols: true (all columns)
  // or an array of column names.
  const rawCol = (hc, c) => hc === true || (Array.isArray(hc) && hc.includes(c));
  const sup = i => `<sup class="lt-fnref">${i}</sup>`;
  // Stringify, mapping null/undefined to "" (0 and false stringify normally).
  // ±Infinity render as ∞/-∞ (ASCII minus, as raw values); formatted columns get
  // the typographic minus via fmtNumber.
  const str = v => v === Infinity ? "∞" : v === -Infinity ? "-∞" : String(v ?? "");

  // --- Number formatting ---
  const isNum = v => typeof v === "number" && isFinite(v);
  // Like isNum but also accepts ±Infinity (which fmtNumber renders as ∞/−∞).
  const isNumInf = v => isNum(v) || Math.abs(v) === Infinity;
  // A column is "numeric" if its first non-null value is a number.
  const numCol = col => col?.length && typeof col.find(v => v != null) === "number";

  // Display label for a column: the last "label" op that names it, else `c`.
  const colLabel = (ops, c) => {
    let lbl = c;
    for (const op of ops) if (op.type === "label" && op.labels?.[c] != null) lbl = op.labels[c];
    return lbl;
  };

  function fmtNumber(v, decimals, bigMark) {
    if (v === Infinity) return "∞";
    if (v === -Infinity) return "−∞";
    if (!isNum(v)) return null;
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
    if (spec.auto_format === false) return;
    const data = spec.data || {}, ops = spec.ops || [],
          colNames = Object.keys(data);

    const fmtCols = new Set();
    for (const op of ops) {
      if (op.type === "fmt_number") for (const c of (op.columns || colNames)) fmtCols.add(c);
    }

    for (const c of colNames) {
      if (fmtCols.has(c)) continue;
      const col = data[c];
      if (!numCol(col)) continue;

      const lbl = colLabel(ops, c),
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
      // Cap: 4 decimals max, minus integer width (so large numbers get fewer).
      // n is already >= 0, so only the upper cap is needed.
      n = Math.min(n, Math.max(4 - maxInt, 0));

      for (let i = 0; i < nRow; i++) {
        const v = col[i];
        if (!isNumInf(v)) continue;
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
      display[c] = data[c].map(str);
    }

    autoFmt(spec, display, nRow);

    // Run fn(col, row, rawValue) over each existing cell of the given columns.
    const eachCell = (cols, fn) => {
      for (const c of cols) {
        if (!data[c]) continue;
        for (let i = 0; i < nRow; i++) fn(c, i, data[c][i]);
      }
    };

    for (const op of ops) {
      const cols = op.columns || colNames;
      switch (op.type) {
        case "fmt_number":
          eachCell(cols, (c, i, raw) => {
            if (!isNumInf(raw)) return;
            const v = op.percent === true ? raw * 100 : raw,
                  psfx = op.percent ? "%" : "",
                  f = fmtNumber(v, op.decimals, op.big_mark ?? ""),
                  pfx = op.prefix || "", sfx = (op.suffix || "") + psfx;
            if (f != null) display[c][i] = pfx + f + sfx;
            else if (pfx || sfx) display[c][i] = pfx + String(v) + sfx;
          });
          break;
        case "fmt_date":
          eachCell(cols, (c, i, raw) => {
            if (raw == null) return;
            const d = raw instanceof Date ? raw : new Date(raw);
            if (isNaN(d)) return;
            display[c][i] = op.method ? d[op.method]() :
              op.options ? d.toLocaleDateString(op.locale, op.options) :
              d.toLocaleDateString(op.locale);
          });
          break;
        case "sub":
          eachCell(cols, (c, i, raw) => {
            if (op.small != null && isNum(raw) && raw !== 0 &&
                Math.abs(raw) < op.small) {
              display[c][i] = op.small_text ?? ("<" + op.small);
            } else if (op.zero != null && raw === 0) {
              display[c][i] = op.zero;
            } else if (op.missing != null && raw == null) {
              display[c][i] = op.missing;
            }
          });
          break;
        case "merge": {
          const mCols = op.columns;
          if (!mCols || mCols.length < 2) break;
          const target = mCols[0];
          for (let i = 0; i < nRow; i++) {
            const vals = mCols.map(c => display[c]?.[i] ?? "");
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
          nRow = colNames.length ? data[colNames[0]].length : 0,
          // Run fn on each op of the given type, in document order.
          onOp = (t, fn) => { for (const op of ops) if (op.type === t) fn(op); };

    // row_group: array → rowspan mode; string → separator-row mode
    let rowGroupSep = typeof spec.row_group === "string";
    const rowGroupCols = Array.isArray(spec.row_group) ? spec.row_group
          : (spec.row_group ? [spec.row_group] : []);
    if (!rowGroupSep && rowGroupCols.length === 1 && spec.auto_sep !== false &&
        !numCol(data[rowGroupCols[0]]) &&
        data[rowGroupCols[0]]?.some(v => (v + "").length > 20)) rowGroupSep = true;

    // Hidden columns: row_group, merge sources
    const hidden = new Set();
    for (const g of rowGroupCols) hidden.add(g);
    onOp("merge", op => {
      if (op.hide !== false && op.columns)
        op.columns.slice(1).forEach(c => hidden.add(c));
    });

    // Visible columns after hiding
    let visible = colNames.filter(c => !hidden.has(c));

    // Apply move
    onOp("move", op => {
      const toMove = (op.columns || []).filter(c => visible.includes(c));
      if (!toMove.length) return;
      const rest = visible.filter(c => !toMove.includes(c));
      if (op.after == null) {
        visible = [...toMove, ...rest];
      } else {
        const pos = rest.indexOf(op.after);
        if (pos >= 0) visible = [...rest.slice(0, pos + 1), ...toMove, ...rest.slice(pos + 1)];
      }
    });

    // Set arr[i] = val where i is the position of column c in `visible`.
    const setByCol = (arr, c, val) => { const i = visible.indexOf(c); if (i >= 0) arr[i] = val; };

    // Alignment: default from data type (number→right, else left), then overrides
    const align = visible.map(c => numCol(data[c]) ? "right" : "left");
    onOp("align", op => { for (const c of (op.columns || [])) setByCol(align, c, op.align); });

    // Column labels
    const autoLbl = s => spec.auto_label === false ? s : s.replace(/[._]/g, " ");
    const colLabels = visible.map(autoLbl);
    onOp("label", op => {
      for (const [c, lbl] of Object.entries(op.labels || {})) setByCol(colLabels, c, lbl);
    });

    // Column widths
    let colWidths = null;
    onOp("width", op => {
      if (!op.widths) return;
      if (!colWidths) colWidths = visible.map(() => "");
      for (const [c, w] of Object.entries(op.widths)) setByCol(colWidths, c, w);
    });

    // Indent
    const indent = new Array(nRow).fill(0);
    onOp("indent", op => {
      if (op.rows) for (const r of op.rows) indent[r - 1] = op.level ?? 1;
    });

    // Runs of equal consecutive values in col → [{ label, rows (1-based) }].
    // Used for both separator-row groups and rowspan span sizes.
    const runs = col => {
      const out = [];
      for (let i = 0; i < nRow;) {
        const label = str(col[i]), rows = [i + 1];
        while (++i < nRow && str(col[i]) === label) rows.push(i + 1);
        out.push({ label, rows });
      }
      return out;
    };

    // Row groups from data column (separator-row mode only). A group label is
    // raw HTML when its source column is flagged raw via html_cols.
    let groups = [];
    if (rowGroupSep && rowGroupCols.length && data[rowGroupCols[0]]) {
      const raw = rawCol(spec.html_cols, rowGroupCols[0]);
      groups.push(...runs(data[rowGroupCols[0]]).map(g => ({ ...g, raw })));
    }
    // Manual groups (labels always escaped; the label comes from an R argument
    // name, which cannot carry an I() raw-HTML marker)
    onOp("row_group", op => groups.push({ label: op.label, rows: op.rows }));
    // Group ordering
    onOp("group_order", op => {
      if (!groups.length) return;
      const ordered = [], rest = [];
      for (const lbl of (op.order || [])) {
        const g = groups.find(x => x.label === lbl);
        if (g) ordered.push(g);
      }
      for (const g of groups) if (!ordered.includes(g)) rest.push(g);
      groups = [...ordered, ...rest];
    });

    // Rowspan groups: compute span sizes for each group column
    const rowSpans = [];
    if (!rowGroupSep && rowGroupCols.length) {
      for (const gc of rowGroupCols) {
        const spans = new Array(nRow).fill(0);
        for (const r of runs(data[gc] || [])) spans[r.rows[0] - 1] = r.rows.length;
        rowSpans.push({ col: gc, label: colLabel(ops, gc), spans });
      }
    }

    // Styles: the style ops are consumed directly (css/class/columns/rows/test).
    const styles = ops.filter(op => op.type === "style");

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
            const mk = visible[k].match(sep);
            if (mk) colLabels[k] = autoLbl(visible[k].slice(mk.index + mk[0].length));
          }
        }
        i = j;
      }
    }

    return {
      visible, align, colLabels, colWidths, indent,
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

  // Find the footnote index for a (type, value) location; 0 if none.
  // `val` is a scalar: the title group, a single column, a spanner label,
  // or a row-group label, depending on `type`.
  const matcher = (fns, idx) => (type, val) => {
    for (const f of fns) {
      const loc = f.location;
      if (loc.type !== type) continue;
      const hit = idx[f.text];
      if (type === "title" && loc.group === val) return hit;
      if (type === "column_labels" && loc.columns.includes(val)) return hit;
      if (type === "column_spanners" && loc.spanners.includes(val)) return hit;
      if (type === "row_groups") {
        if (loc.match === "all") return hit;
        if (loc.match === "exact" && loc.values.includes(val)) return hit;
        if (loc.match === "starts_with" && val.startsWith(loc.value)) return hit;
      }
    }
    return 0;
  };

  function sortByGroups(spec) {
    if (spec.sort === false || !spec.row_group) return;
    const data = spec.data || {},
          cols = [].concat(spec.row_group),
          colNames = Object.keys(data),
          nRow = colNames.length ? data[colNames[0]].length : 0;
    if (!nRow) return;
    const idx = Array.from({length: nRow}, (_, i) => i);
    idx.sort((a, b) => {
      for (const c of cols) {
        const va = data[c]?.[a], vb = data[c]?.[b];
        if (va == vb) continue;
        if (va == null) return 1;
        if (vb == null) return -1;
        if (va < vb) return -1;
        if (va > vb) return 1;
      }
      return 0;
    });
    for (const c of colNames) data[c] = idx.map(i => data[c][i]);
    // Remap 1-based row indices in ops to reflect the new order
    const newPos = new Array(nRow);
    for (let i = 0; i < nRow; i++) newPos[idx[i]] = i + 1;
    for (const op of (spec.ops || [])) {
      if (op.rows) op.rows = op.rows.map(r => newPos[r - 1]);
    }
  }

  function buildHtml(spec) {
    sortByGroups(spec);
    const data = spec.data || {},
          { display, nRow } = applyOps(spec),
          { visible: cols, align, colLabels, colWidths, indent,
            groups, rowSpans, styles, spanners, footnotes: fns, notes, header: hdr } = resolveSpec(spec),
          reg = indexFootnotes(fns),
          fIdx = matcher(fns, reg.idx),
          nGrp = rowSpans.length,
          nCol = cols.length + nGrp,
          // Whether column `c`'s body cells are raw HTML (see lt_html() on the
          // R side); spec.html_cols is true (all columns) or a name array.
          isRaw = c => rawCol(spec.html_cols, c),
          out = [`<table class="lt-table">`];
    const mark = (type, val) => { const i = fIdx(type, val); return i ? sup(i) : ""; };
    const cell = (c, r) => display[c]?.[r - 1] ?? "";
    // ` name="val"` for a truthy val, else "" — for optional HTML attributes.
    const attr = (n, v) => v ? ` ${n}="${v}"` : "";
    // Plain class names per column (alignment + leading-indent), "" if none.
    const colCls = cols.map((_, i) => (
      (i === 0 && groups.length ? "lt-indent " : "") +
      ({right: "al-r", center: "al-c"}[align[i]] || "")
    ).trimEnd());

    // Visit each cell at (rows × cols) that exists in the table, calling
    // fn(key, c, r). rows null = all rows; cols falls back to all columns.
    const eachLoc = (rows, locCols, fn) => {
      for (let r = 1; r <= nRow; r++) {
        if (rows && !rows.includes(r)) continue;
        for (const c of (locCols || cols)) {
          const ci = cols.indexOf(c);
          if (ci >= 0) fn(`${r},${ci}`, c, r);
        }
      }
    };

    // Style map: accumulate css (";") and class (" ") per cell.
    const styleMap = {}, classMap = {};
    const addTo = (map, key, val, sep) => { map[key] = map[key] ? map[key] + sep + val : val; };
    for (const s of styles)
      eachLoc(s.rows, s.columns ? [].concat(s.columns) : null, (key, c, r) => {
        if (s.test && !s.test(data[c][r - 1])) return;
        if (s.css) addTo(styleMap, key, s.css, ";");
        if (s.class) addTo(classMap, key, s.class, " ");
      });

    // <colgroup>: leading empty <col>s for rowspan group columns, so widths
    // align with the body columns (which are offset by nGrp on the left).
    if (colWidths && colWidths.some(w => w)) {
      out.push(`<colgroup>`);
      for (let i = 0; i < nGrp; i++) out.push(`<col>`);
      for (let i = 0; i < cols.length; i++)
        out.push(`<col${attr("style", colWidths[i] ? "width:" + colWidths[i] : "")}>`);
      out.push(`</colgroup>`);
    }

    // <caption>: title + subtitle, each a <div> rendered only when non-empty.
    const caption = [["title", "lt-title"], ["subtitle", "lt-subtitle"]]
      .filter(([g]) => hdr[g] != null && hdr[g] !== "")
      .map(([g, cls]) => `<div class="${cls}">${txt(hdr[g])}${mark("title", g)}</div>`);
    if (caption.length)
      out.push(`<caption class="lt-caption">`, ...caption, `</caption>`);

    // <thead>
    out.push(`<thead>`);
    if (spanners.length) {
      const emptyTh = `<th class="lt-spanner-empty"></th>`;
      out.push(`<tr class="lt-spanner-row">`);
      out.push(emptyTh.repeat(nGrp));
      for (let k = 0; k < cols.length;) {
        const sp = spanners.find(s => s.columns[0] === cols[k]);
        if (sp) {
          out.push(`<th colspan="${sp.columns.length}" scope="colgroup" class="lt-spanner">${txt(sp.label)}${mark("column_spanners", sp.label)}</th>`);
          k += sp.columns.length;
        } else {
          out.push(emptyTh);
          k++;
        }
      }
      out.push(`</tr>`);
    }
    out.push(`<tr>`);
    for (const rs of rowSpans) out.push(`<th scope="col">${txt(rs.label)}</th>`);
    for (let i = 0; i < cols.length; i++)
      out.push(`<th scope="col"${attr("class", colCls[i])}>${txt(colLabels[i])}${mark("column_labels", cols[i])}</th>`);
    out.push(`</tr></thead>`);

    // Body footnote markers
    const bodyMarks = {};
    for (const f of fns) {
      if (f.location.type !== "body") continue;
      const fi = reg.idx[f.text];
      eachLoc(f.location.rows, f.location.columns || [], key => { bodyMarks[key] = fi; });
    }

    // Row rendering
    const pushRow = r => {
      out.push(`<tr>`);
      // Row-group cells. For a group spanning n > 1 rows, the label goes in a
      // non-spanning cell on the first row — so vertical-align centers it
      // within that row's height (matching the body cells) instead of across
      // the whole span — followed by an empty filler cell spanning the
      // remaining n - 1 rows. A single-row group is just the label cell.
      for (const rs of rowSpans) {
        const span = rs.spans[r - 1], fill = (rs.spans[r - 2] || 0) - 1;
        if (span > 0)
          out.push(`<th scope="row" class="lt-row-group${span > 1 ? " lt-row-open" : ""}">${escIf(isRaw(rs.col), cell(rs.col, r))}</th>`);
        else if (fill > 0)
          out.push(`<th class="lt-row-group"${attr("rowspan", fill > 1 ? fill : 0)}></th>`);
      }
      const ind = indent[r - 1] || 0;
      for (let ci = 0; ci < cols.length; ci++) {
        const k = `${r},${ci}`, c = cols[ci],
              m = bodyMarks[k], cc = classMap[k],
              cls = [colCls[ci], cc].filter(Boolean).join(" ");
        let s = styleMap[k] || "";
        if (ci === 0 && ind) s = (s ? s + ";" : "") + `padding-left:${ind + 1}em`;
        const raw = str(data[c][r - 1]), disp = display[c][r - 1],
              tip = raw !== disp ? ` title="${esc(raw)}"` : "";
        out.push(`<td${attr("class", cls)}${attr("style", s)}${tip}>${escIf(isRaw(c), disp)}${m ? sup(m) : ""}</td>`);
      }
      out.push(`</tr>`);
    };

    // <tbody>
    out.push(`<tbody>`);
    if (groups.length) {
      const seen = {};
      for (const g of groups) {
        out.push(`<tr class="lt-row-group"><th colspan="${nCol}" scope="colgroup">${escIf(g.raw, g.label)}${mark("row_groups", g.label)}</th></tr>`);
        for (const r of g.rows) { seen[r] = 1; pushRow(r); }
      }
      for (let r = 1; r <= nRow; r++) if (!seen[r]) pushRow(r);
    } else {
      for (let r = 1; r <= nRow; r++) pushRow(r);
    }
    out.push(`</tbody>`);

    // <tfoot>: footnotes then source notes, each a full-width row.
    if (reg.order.length || notes.length) {
      const footRow = (cls, html) => `<tr class="${cls}"><td colspan="${nCol}">${html}</td></tr>`;
      out.push(`<tfoot class="lt-footer">`);
      reg.order.forEach((t, i) => out.push(footRow("lt-footnote", `${sup(i + 1)} ${txt(t)}`)));
      for (const n of notes) out.push(footRow("lt-source-note", txt(n)));
      out.push(`</tfoot>`);
    }

    out.push(`</table>`);
    // Wrap in a div so a wide table can scroll horizontally (`overflow-x`)
    // instead of overflowing the page.
    return `<div class="lt-wrap">${out.join("")}</div>`;
  }

  const mount = (s, spec) => {
    s.insertAdjacentHTML("afterend", buildHtml(spec));
    const tbl = s.nextElementSibling.querySelector("table"),
          raw = (e, el) => e.altKey && el.classList.toggle("lt-raw");
    tbl.onclick = e => e.detail === 1 && raw(e, tbl);
    tbl.ondblclick = e => raw(e, tbl.ownerDocument.documentElement);
  };
  // q.push renders immediately; replay any entries queued before we loaded.
  const q = { push: e => mount(e.s, e.d) };
  (root.LT?.q || []).forEach(q.push);
  root.LT = { build: spec => mount(document.currentScript, spec), buildHtml, q };
})(window);
