/* lt.js — build semantic <table> from JSON spec.
 * LT.build(spec) from inline <script> renders in place; LT.render(el, spec)
 * renders into container anytime. One runtime per page serves all tables.
 */
(root => {
  "use strict";
  if (root.LT?.buildHtml) return;  // duplicate include: no-op

  // DOM helpers, shared with the extensions via LT.
  const $ = (el, sel) => el.querySelector(sel),
        $$ = (el, sel) => el.querySelectorAll(sel),
        on = (t, type, fn, opts) => t.addEventListener(type, fn, opts),
        off = (t, type, fn) => t.removeEventListener(type, fn);

  // Inline-graphics cell renderers keyed by op type, registered by lt-plot.js
  // (loaded before core). Live reference re-exposed on root.LT, so plot
  // module loaded before or after core registers into same object. Empty
  // without plot module; core has no plot code (see LT.cells docs).
  const cellRenderers = root.LT?.cells || {};

  // `[<]` not `<` avoids `</…`, so file is safe to inline in <script>.
  const esc = s => String(s)
    .replace(/&/g, "&amp;").replace(/[<]/g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  // Text fields arrive as plain string (escape) or, if wrapped in I() in R,
  // one-element array (verbatim raw HTML). `txt` handles both.
  const txt = v => Array.isArray(v) ? String(v[0] ?? "") : esc(v);
  // Raw if `raw`, else escaped; for already-stringified values (e.g. cells of
  // columns in spec.html_cols).
  const escIf = (raw, s) => raw ? String(s ?? "") : esc(s);
  // Column `c` raw HTML? `hc` = spec.html_cols: true (all) or column names.
  const rawCol = (hc, c) => hc === true || (Array.isArray(hc) && hc.includes(c));
  const sup = i => `<sup class="lt-fnref">${i}</sup>`;
  // Stringify; null/undefined -> "". ±Infinity -> ∞/-∞ (ASCII minus, raw
  // values); formatted columns get typographic minus via fmtNumber.
  const str = v => v === Infinity ? "∞" : v === -Infinity ? "-∞" : String(v ?? "");

  // --- Number formatting ---
  const isNum = v => typeof v === "number" && isFinite(v);
  // Like isNum, plus ±Infinity (fmtNumber renders ∞/−∞).
  const isNumInf = v => isNum(v) || Math.abs(v) === Infinity;
  // Numeric column: first non-null value is a number.
  const numCol = col => col?.length && typeof col.find(v => v != null) === "number";

  // Column order: prefer spec.columns from R; JSON objects put integer-like
  // keys ("1", "2") first, so Object.keys(data) would scramble numeric names.
  const colOrder = spec => (spec.columns || Object.keys(spec.data || {}))
    .filter(c => c in (spec.data || {}));

  // Column label: last "label" op naming it, else `c`.
  const colLabel = (ops, c) => {
    let lbl = c;
    for (const op of ops) if (op.type === "label" && op.labels?.[c] != null) lbl = op.labels[c];
    return lbl;
  };

  // Expand exponential notation ("4.2e+3") to plain decimal, keeping
  // toPrecision digits.
  function expandExp(s) {
    if (!/e/i.test(s)) return s;
    const [, sign, int, frac = "", expStr] =
      s.match(/^(-?)(\d+)(?:\.(\d+))?e([+-]?\d+)$/i);
    const exp = +expStr, digits = int + frac, point = int.length + exp;
    let out;
    if (point <= 0) out = `0.${"0".repeat(-point)}${digits}`;
    else if (point >= digits.length) out = digits + "0".repeat(point - digits.length);
    else out = `${digits.slice(0, point)}.${digits.slice(point)}`;
    return sign + out;
  }

  function fmtNumber(v, decimals, bigMark, sigDigits) {
    if (v === Infinity) return "∞";
    if (v === -Infinity) return "−∞";
    if (!isNum(v)) return null;
    let s = sigDigits != null ? expandExp(v.toPrecision(sigDigits)) :
            decimals != null ? v.toFixed(decimals) : String(v);
    if (/^-0(\.0+)?$/.test(s)) s = s.slice(1);
    if (bigMark) {
      const parts = s.split(".");
      parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, bigMark);
      s = parts.join(".");
    }
    if (s[0] === "-") s = `−${s.slice(1)}`;
    return decimals != null || bigMark || sigDigits != null ? s : null;
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
    vals.forEach((v, i) => s = s.split(`{${i + 1}}`).join(v));
    return s;
  }

  // --- Auto-format numeric columns ---
  function autoFmt(spec, display, nRow) {
    if (spec.auto_format === false) return;
    const data = spec.data || {}, ops = spec.ops || [],
          colNames = colOrder(spec);

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

      // Decimals: max significant decimals across column, capped by
      // largest integer-part width (~4 significant digits): <1 up to 4,
      // 10-99 2, >=1000 0.
      let maxInt = 0, n = 0;
      for (const v of col) {
        if (!isNum(v)) continue;
        // Integer digits
        const a = Math.abs(pct ? v * 100 : v),
              intW = a < 1 ? 0 : Math.floor(Math.log10(a)) + 1;
        if (intW > maxInt) maxInt = intW;
        // Significant decimals (trailing zeros stripped; pct adjusts
        // *100)
        const m = String(v).match(/\.(\d+)/);
        if (!m) continue;
        const d = m[1].replace(/0+$/, "").length - (pct ? 2 : 0);
        if (d > n) n = d;
      }
      // Cap 4 decimals minus integer width; n >= 0, so only upper cap.
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
          colNames = colOrder(spec),
          nRow = colNames.length ? data[colNames[0]].length : 0;

    // display[col][row] = string
    const display = {};
    for (const c of colNames) {
      display[c] = data[c].map(str);
    }

    autoFmt(spec, display, nRow);

    // Run fn(col, row, raw) over existing cells of columns.
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
                  f = fmtNumber(v, op.decimals, op.big_mark ?? "", op.sig_digits),
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
              display[c][i] = op.small_text ?? `<${op.small}`;
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

    // Missing (null/NA) default: em dash unless spec.missing overrides (""
    // = blank). Per-column lt_sub(missing=) already filled above, so only
    // still-empty null cells get default; empty strings stay.
    const miss = spec.missing === undefined ? "—" : spec.missing;
    if (miss) {
      for (const c of colNames)
        for (let i = 0; i < nRow; i++)
          if (data[c][i] == null && display[c][i] === "") display[c][i] = miss;
    }

    return { display, nRow };
  }

  // --- Resolve structural spec fields from ops + data ---
  function resolveSpec(spec) {
    const data = spec.data || {},
          ops = spec.ops || [],
          colNames = colOrder(spec),
          nRow = colNames.length ? data[colNames[0]].length : 0,
          // Run fn on each op of type, in document order.
          onOp = (t, fn) => { for (const op of ops) if (op.type === t) fn(op); };

    // row_group: array = rowspan mode; string = separator-row mode
    let rowGroupSep = typeof spec.row_group === "string";
    const rowGroupCols = Array.isArray(spec.row_group) ? spec.row_group
          : (spec.row_group ? [spec.row_group] : []);
    if (!rowGroupSep && rowGroupCols.length === 1 && spec.auto_sep !== false &&
        !numCol(data[rowGroupCols[0]]) &&
        data[rowGroupCols[0]]?.some(v => (v + "").length > 20)) rowGroupSep = true;

    // Hidden columns: row_group, merge sources, explicit hide op
    const hidden = new Set();
    for (const g of rowGroupCols) hidden.add(g);
    onOp("merge", op => {
      if (op.hide !== false && op.columns)
        op.columns.slice(1).forEach(c => hidden.add(c));
    });
    onOp("hide", op => (op.columns || []).forEach(c => hidden.add(c)));

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

    // arr[i] = val, i = position of c in `visible`.
    const setByCol = (arr, c, val) => { const i = visible.indexOf(c); if (i >= 0) arr[i] = val; };

    // Alignment: default from data type (number→right, else left), then overrides
    const align = visible.map(c => numCol(data[c]) ? "right" : "left");
    onOp("align", op => { for (const c of (op.columns || [])) setByCol(align, c, op.align); });

    // Column labels
    const autoLbl = s => spec.auto_label === false ? s : s.replace(/[._]/g, " "),
          colLabels = visible.map(autoLbl);
    onOp("label", op => {
      for (const [c, lbl] of Object.entries(op.labels || {})) setByCol(colLabels, c, lbl);
    });

    // Column widths + whole-table width
    let colWidths, tableWidth;
    onOp("width", op => {
      if (op.table) tableWidth = op.table;
      if (!op.widths) return;
      if (!colWidths) colWidths = visible.map(() => "");
      for (const [c, w] of Object.entries(op.widths)) setByCol(colWidths, c, w);
    });

    // Indent
    const indent = new Array(nRow).fill(0);
    onOp("indent", op => {
      if (op.rows) for (const r of op.rows) indent[r - 1] = op.level ?? 1;
    });

    // Runs of equal consecutive values in col -> [{label, rows (1-based)}];
    // for separator groups and rowspans.
    const runs = col => {
      const out = [];
      for (let i = 0; i < nRow;) {
        const label = str(col[i]), rows = [i + 1];
        while (++i < nRow && str(col[i]) === label) rows.push(i + 1);
        out.push({ label, rows });
      }
      return out;
    };

    // Row groups from data column (separator mode); label raw if source
    // column in html_cols.
    let groups = [];
    if (rowGroupSep && rowGroupCols.length && data[rowGroupCols[0]]) {
      const raw = rawCol(spec.html_cols, rowGroupCols[0]);
      groups.push(...runs(data[rowGroupCols[0]]).map(g => ({ ...g, raw })));
    }
    // Manual groups (label always escaped: comes from R arg name, cannot
    // carry I())
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

    // Explicit spanners: reorder columns to final (post-move) body order.
    // Spanner matches visual position of first column, then spans next
    // columns.length cells, so a non-leftmost first column would misalign
    // header.
    let spanners = (spec.spanners || []).map(sp => {
      const cols = sp.columns.slice().sort((a, b) => visible.indexOf(a) - visible.indexOf(b));
      return { ...sp, columns: cols };
    });
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

    // Inline-graphics cells: op type with renderer on LT.cells (from
    // lt-plot.js) draws its value column as inline SVG. Renderer maps op to
    // per-column config; pushRow and footer consult cellMap[col] = { rnd,
    // cfg }.
    const cellMap = {};
    for (const op of ops) {
      const rnd = cellRenderers[op.type];
      if (!rnd) continue;
      const cfgs = rnd.resolve(op) || {};
      for (const c of Object.keys(cfgs)) cellMap[c] = { rnd, cfg: cfgs[c] };
    }

    return {
      visible, align, colLabels, colWidths, tableWidth, indent,
      groups, rowSpans, styles, spanners, cellMap,
      footnotes: spec.footnotes || [],
      notes: spec.notes || [],
      header: spec.header || {},
      nRow
    };
  }

  // Footnotes: dedup by text, number 1..N by first appearance.
  function indexFootnotes(fns) {
    const order = [], idx = {};
    fns.forEach(f => {
      if (idx[f.text] == null) { idx[f.text] = order.length + 1; order.push(f.text); }
    });
    return { order, idx };
  }

  // Footnote index for (type, value) location; 0 if none. `val` scalar: title
  // group, column, spanner label, or row-group label, per `type`.
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
          colNames = colOrder(spec),
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
    // Remap 1-based row indices in ops to new order
    const newPos = new Array(nRow);
    for (let i = 0; i < nRow; i++) newPos[idx[i]] = i + 1;
    for (const op of (spec.ops || [])) {
      if (op.rows) op.rows = op.rows.map(r => newPos[r - 1]);
    }
  }

  // Materialize `add_col` ops: empty column (op.value ?? "") from shipped
  // name, so runtime treats it as ordinary. Appended last (lt_move()
  // positions it).
  function addColumns(spec) {
    const data = spec.data || (spec.data = {}),
          nRow = data[colOrder(spec)[0]]?.length || 0;
    for (const op of (spec.ops || []))
      if (op.type === "add_col" && op.column && !(op.column in data)) {
        data[op.column] = new Array(nRow).fill(op.value ?? "");
        // keep new column in explicit column order, if shipped
        if (spec.columns && !spec.columns.includes(op.column))
          spec.columns = [...spec.columns, op.column];
      }
  }

  function buildHtml(spec) {
    sortByGroups(spec);
    addColumns(spec);
    const data = spec.data || {},
          { display, nRow } = applyOps(spec),
          { visible: cols, align, colLabels, colWidths, tableWidth, indent,
            groups, rowSpans, styles, spanners, cellMap, footnotes: fns, notes, header: hdr } = resolveSpec(spec),
          // Core helpers for cell renderer (see LT.cells /
          // lt-plot.js).
          U = { esc, isNum, str },
          reg = indexFootnotes(fns),
          fIdx = matcher(fns, reg.idx),
          nGrp = rowSpans.length,
          nCol = cols.length + nGrp,
          // Column `c` body cells raw HTML? (see lt_html() in R);
          // spec.html_cols true or names.
          isRaw = c => rawCol(spec.html_cols, c),
          out = [`<table class="lt-table"${tableWidth ? ` style="width:${tableWidth}"` : ""}>`],
          // Cap initial render to first page (pager[0], 0 = all) so
          // huge tables don't build whole row string before plugin
          // pages. Only when plugin loaded to page rest in; static
          // bake renders all. `_viewRows` overrides.
          pg = root.LT?.plugins?.interactive && spec.interactive?.pager,
          lim = (!spec._viewRows && Array.isArray(pg) && pg[0]) ? pg[0] : 0;
    const mark = (type, val) => { const i = fIdx(type, val); return i ? sup(i) : ""; },
          cell = (c, r) => display[c]?.[r - 1] ?? "";
    // ` name="val"` if val truthy, else "" (optional attrs).
    const attr = (n, v) => v ? ` ${n}="${v}"` : "";
    // Plain class names per column (alignment + indent), "" if none.
    const colCls = cols.map((_, i) => (
      (i === 0 && groups.length ? "lt-indent " : "") +
      ({right: "al-r", center: "al-c"}[align[i]] || "")
    ).trimEnd());

    // Visit existing cells at rows x cols, calling fn(key, c, r). rows null
    // = all; cols default all.
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

    // <colgroup>: leading empty <col>s for rowspan group columns, aligning
    // widths with body columns (offset nGrp).
    if (colWidths && colWidths.some(w => w)) {
      out.push(`<colgroup>`);
      if (nGrp) out.push("<col>".repeat(nGrp));
      colWidths.forEach(w => out.push(`<col${attr("style", w ? `width:${w}` : "")}>`));
      out.push(`</colgroup>`);
    }

    // <caption>: title + subtitle, each <div> only if non-empty.
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
    for (const rs of rowSpans)
      out.push(`<th scope="col" class="lt-row-group">${txt(rs.label)}</th>`);
    cols.forEach((c, i) =>
      out.push(`<th scope="col"${attr("class", colCls[i])}>${txt(colLabels[i])}${mark("column_labels", c)}</th>`));
    out.push(`</tr></thead>`);

    // Body footnote markers
    const bodyMarks = {};
    for (const f of fns) {
      if (f.location.type !== "body") continue;
      const fi = reg.idx[f.text];
      eachLoc(f.location.rows, f.location.columns || [], key => { bodyMarks[key] = fi; });
    }

    // Row rendering
    const pushRow = (r, spanCells) => {
      out.push(`<tr>`);
      // Row-group cells. Group spanning n > 1 rows: label in non-spanning
      // cell on first row (vertical-align centers within that row like
      // body cells, not across span), then empty filler spanning
      // remaining n - 1 rows. Single-row group: label cell only.
      // Per-column descriptor ({label, open} label cell, {fill} filler,
      // nothing if covered above) comes from caller for reordered rows
      // (`spanCells`, view order), else from file-order spans.
      for (let gi = 0; gi < rowSpans.length; gi++) {
        const rs = rowSpans[gi];
        let d = spanCells ? spanCells[gi] : null;
        if (!spanCells) {
          const span = rs.spans[r - 1], fill = (rs.spans[r - 2] || 0) - 1;
          d = span > 0 ? { label: true, open: span > 1 } : fill > 0 ? { fill } : null;
        }
        if (!d) continue;
        if (d.label)
          out.push(`<th scope="row" class="lt-row-group${d.open ? " lt-row-open" : ""}">${escIf(isRaw(rs.col), cell(rs.col, r))}${mark("row_groups", str(data[rs.col][r - 1]))}</th>`);
        else
          out.push(`<th class="lt-row-group"${attr("rowspan", d.fill > 1 ? d.fill : 0)}></th>`);
      }
      const ind = indent[r - 1] || 0;
      for (let ci = 0; ci < cols.length; ci++) {
        const k = `${r},${ci}`, c = cols[ci],
              m = bodyMarks[k], cc = classMap[k],
              cls = [colCls[ci], cc].filter(Boolean).join(" ");
        let s = styleMap[k] || "";
        if (ci === 0 && ind) s = (s ? s + ";" : "") + `padding-left:${ind + 1}em`;
        const cm = cellMap[c];
        if (cm) {
          // Plot cell: renderer supplies inner SVG, may add <td>
          // class (e.g. zero padding for unbroken gridlines).
          const extra = cm.rnd.cellClass?.(cm.cfg) || "",
                pcls = [cls, extra].filter(Boolean).join(" ");
          out.push(`<td${attr("class", pcls)}${attr("style", s)}>${cm.rnd.cell(cm.cfg, data, r, U)}${m ? sup(m) : ""}</td>`);
          continue;
        }
        const raw = str(data[c][r - 1]), disp = display[c][r - 1],
              tip = raw !== disp ? ` title="${esc(raw)}"` : "";
        out.push(`<td${attr("class", cls)}${attr("style", s)}${tip}>${escIf(isRaw(c), disp)}${m ? sup(m) : ""}</td>`);
      }
      out.push(`</tr>`);
    };

    // Separator row-group header: one full-width cell with label.
    const groupHeader = (label, raw) =>
      `<tr class="lt-row-group"><th colspan="${nCol}" scope="colgroup">${escIf(raw, label)}${mark("row_groups", label)}</th></tr>`;

    // Rowspan group cells for reordered view: file-order `rs.spans` no
    // longer fit, so walk view sequence, grouping rows into runs sharing
    // group-value prefix (column gi's run breaks when its or any earlier
    // group column's value changes). Run's first row gets label cell,
    // second a filler spanning rest, others nothing. Returns descriptor
    // array per view position (pushRow's `spanCells`).
    const viewRowSpans = seq => {
      const info = seq.map(() => []);
      for (let gi = 0; gi < rowSpans.length; gi++) {
        const key = r => rowSpans.slice(0, gi + 1)
          .map(rs => str(data[rs.col][r - 1])).join("\u0000");
        for (let i = 0; i < seq.length;) {
          let j = i + 1;
          const k = key(seq[i]);
          while (j < seq.length && key(seq[j]) === k) j++;
          const len = j - i;
          info[i][gi] = { label: true, open: len > 1 };
          if (len > 1) info[i + 1][gi] = { fill: len - 1 };
          i = j;
        }
      }
      return info;
    };

    // <tbody>. Optional `spec._viewRows` sets row order/subset: seam for
    // interactive plugin sort/filter without reimplementing row rendering.
    // Entry = 1-based original row index or, for grouped tables, `{label,
    // raw}` separator header the plugin re-emits. Overrides file-order
    // branches (static table). Row-indexed styles/footnotes/indent stay
    // keyed to original indices. Rowspan mode recomputes spans from view
    // order (viewRowSpans).
    out.push(`<tbody>`);
    if (spec._viewRows) {
      const info = rowSpans.length ?
        viewRowSpans(spec._viewRows.filter(r => typeof r === "number")) : null;
      let vi = 0;
      for (const r of spec._viewRows)
        if (r && typeof r === "object") out.push(groupHeader(r.label, r.raw));
        else pushRow(r, info ? info[vi++] : null);
    } else if (groups.length) {
      const seen = {};
      let n = 0;
      for (const g of groups) {
        if (lim && n >= lim) break;
        out.push(groupHeader(g.label, g.raw));
        for (const r of g.rows) { seen[r] = 1; pushRow(r); if (lim && ++n >= lim) break; }
      }
      for (let r = 1; r <= nRow && (!lim || n < lim); r++)
        if (!seen[r]) { pushRow(r); n++; }
    } else {
      const end = lim ? Math.min(nRow, lim) : nRow;
      for (let r = 1; r <= end; r++) pushRow(r);
    }
    out.push(`</tbody>`);

    // <tfoot>: optional plot-footer row (e.g. shared error-bar axis), then
    // footnotes and source notes. Footer row has per-column cell so each
    // renderer's footer SVG aligns under its plot column; note rows span
    // full width.
    const footCells = cols.map(c =>
      cellMap[c] ? (cellMap[c].rnd.foot?.(cellMap[c].cfg, U) || "") : "");
    const hasFoot = footCells.some(h => h);
    if (reg.order.length || notes.length || hasFoot) {
      const footRow = (cls, html) => `<tr class="${cls}"><td colspan="${nCol}">${html}</td></tr>`;
      out.push(`<tfoot class="lt-footer">`);
      if (hasFoot) {
        out.push(`<tr class="lt-plot-foot">`);
        out.push(`<td></td>`.repeat(nGrp));
        cols.forEach((c, i) => {
          const cm = cellMap[c];
          // reuse renderer's cell class to align footer with plot
          const extra = footCells[i] && cm ? (cm.rnd.cellClass?.(cm.cfg) || "") : "",
                ac = [colCls[i], extra].filter(Boolean).join(" ");
          out.push(`<td${attr("class", ac)}>${footCells[i]}</td>`);
        });
        out.push(`</tr>`);
      }
      reg.order.forEach((t, i) => out.push(footRow("lt-footnote", `${sup(i + 1)} ${txt(t)}`)));
      for (const n of notes) out.push(footRow("lt-source-note", txt(n)));
      out.push(`</tfoot>`);
    }

    out.push(`</table>`);
    // Expose resolved visible column order (after hide/move) for plugin
    // sort/filter. Side effect only; core never reads it; harmless for
    // static/Node.
    spec._cols = cols;
    // Also formatted cell text (all columns, hidden too), so plugins can
    // show displayed values (e.g. row detail).
    spec._display = display;
    // Expose resolved row structure for interactive plugin: separator
    // groups ({label, rows, raw}), per-row indent levels (array or null),
    // rowspan group columns (outermost first, or null). Plugin
    // sorts/filters within each run and recomputes spans in view order (see
    // viewRowSpans).
    spec._groups = groups.length ? groups : null;
    spec._indent = indent.some(v => v) ? indent : null;
    spec._rowspan = rowSpans.length ? rowSpans.map(rs => rs.col) : null;
    // Wrap in div so wide tables scroll horizontally (`overflow-x`).
    // `spec.wrap` (lt_wrap()) gives attributes: `class` appended to base
    // `lt-wrap`, rest emitted escaped; hook for scoped CSS, id, fixed
    // width.
    const w = spec.wrap || {}, cls = ["lt-wrap"].concat(w.class || []).join(" ");
    const wa = Object.keys(w).filter(k => k !== "class")
      .map(k => attr(k, esc(w[k]))).join("");
    return `<div${attr("class", cls)}${wa}>${out.join("")}</div>`;
  }

  // Plugin seam (lt-interactive.js): plugin attaches handle under LT.plugins
  // and pushes callback onto LT.onMount; core calls it with each table
  // element and spec after mount.
  // Cell-renderer seam (lt-plot.js): module registers renderer under LT.cells
  // by op type; core consults it *during* buildHtml to draw a column's cells
  // and optional footer.
  const plugins = root.LT?.plugins || {}, onMount = root.LT?.onMount || [];

  // Alt-click toggles raw values in this table; alt-dblclick page-wide.
  // Handlers must not *return* false (cancels click default, e.g. checkbox in
  // table wouldn't toggle), so use statement bodies.
  const wireRaw = tbl => {
    const raw = (e, el) => { if (e.altKey) el.classList.toggle("lt-raw"); };
    tbl.onclick = e => { if (e.detail === 1) raw(e, tbl); };
    tbl.ondblclick = e => { raw(e, tbl.ownerDocument.documentElement); };
  };

  // Finish inserted table: remember spec, wire raw toggle, let plugins
  // enhance. Returns table element.
  const ready = (tbl, spec) => {
    // Stash spec so plugin loaded *after* mount (usual: core drains queue
    // before plugin file runs) can find and enhance it by scanning
    // `.lt-table`.
    tbl._ltSpec = spec;
    // Map visible column to header cell, for plugins tracking a column
    // (e.g. width). Built before plugins add <thead> rows, so last header
    // row is labels; nGrp offsets data columns.
    const hr = tbl.tHead && [...tbl.tHead.rows].pop(),
          nGrp = (spec._rowspan || []).length;
    if (hr) {
      const m = tbl._ltHead = {};
      (spec._cols || []).forEach((c, i) => m[c] = hr.cells[nGrp + i]);
    }
    wireRaw(tbl);
    onMount.forEach(f => f(tbl, spec));
    return tbl;
  };

  // `data_key` names data shared across tables in LT.d; shallow-copy so
  // per-table column changes don't leak into the shared store.
  const store = root.LT?.d || {}, mount = (s, spec) => {
    if (spec.data_key) spec.data = {...store[spec.data_key]};
    s.insertAdjacentHTML("afterend", buildHtml(spec));
    ready($(s.nextElementSibling, "table"), spec);
  };

  // Render spec into `el` (replacing content) anytime, e.g. on-demand tables
  // long after load. Unlike build(), needs no anchoring <script>; caller may
  // keep returned table.
  const render = (el, spec) => {
    el.innerHTML = buildHtml(spec);
    return ready($(el, "table"), spec);
  };
  // Rebuild mounted table in place from stashed spec. For cell module
  // (lt-plot.js) loading *after* core built a table (e.g. earlier plain table
  // pulled in lt.js first): module registers renderer, then refreshes tables
  // needing it.
  const refresh = tbl => {
    const spec = tbl?._ltSpec, wrap = tbl?.closest(".lt-wrap");
    if (!spec || !wrap) return;
    wrap.insertAdjacentHTML("afterend", buildHtml(spec));
    const next = wrap.nextElementSibling;
    wrap.remove();
    return ready($(next, "table"), spec);
  };
  // q.push renders now; replay entries queued before load.
  const q = { push: e => mount(e.s, e.d) };
  (root.LT?.q || []).forEach(q.push);
  root.LT = {
    build: spec => mount(document.currentScript, spec),
    render, refresh, buildHtml, plugins, onMount, cells: cellRenderers, q, d: store,
    $, $$, on, off, numCol,
  };
})(window);
