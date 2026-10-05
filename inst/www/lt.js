/* lt.js — build a semantic <table> from a JSON spec.
 * Call LT.build(spec) from an inline <script> to render a table in place, or
 * LT.render(el, spec) to render one into a container at any later time.
 * One runtime per page renders any number of tables.
 */
(root => {
  "use strict";
  if (root.LT?.buildHtml) return;  // duplicate inclusion is a no-op

  const $ = (el, sel) => el.querySelector(sel);

  // Inline-graphics cell renderers (error bars, sparklines, …), keyed by op
  // type and shipped by lt-plot.js (loaded before core). Captured as a live
  // reference and re-exposed on root.LT below, so a plot module loaded either
  // before or after core registers into the same object. Empty when no plot
  // module is present; core itself contains no plot code (see LT.cells docs).
  const cellRenderers = root.LT?.cells || {};

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

  // Column order. Prefer the explicit `spec.columns` sent by R: a JSON object
  // reorders integer-like keys (e.g. "1", "2") ahead of string keys, so
  // Object.keys(data) alone would scramble columns whose names are numbers.
  const colOrder = spec => (spec.columns || Object.keys(spec.data || {}))
    .filter(c => c in (spec.data || {}));

  // Display label for a column: the last "label" op that names it, else `c`.
  const colLabel = (ops, c) => {
    let lbl = c;
    for (const op of ops) if (op.type === "label" && op.labels?.[c] != null) lbl = op.labels[c];
    return lbl;
  };

  // Expand JS exponential notation (e.g. "4.2e+3") to plain decimal,
  // preserving the significant digits produced by toPrecision.
  function expandExp(s) {
    if (!/e/i.test(s)) return s;
    const [, sign, int, frac = "", expStr] =
      s.match(/^(-?)(\d+)(?:\.(\d+))?e([+-]?\d+)$/i);
    const exp = +expStr, digits = int + frac, point = int.length + exp;
    let out;
    if (point <= 0) out = "0." + "0".repeat(-point) + digits;
    else if (point >= digits.length) out = digits + "0".repeat(point - digits.length);
    else out = digits.slice(0, point) + "." + digits.slice(point);
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
    if (s[0] === "-") s = "−" + s.slice(1);
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
    for (let i = 0; i < vals.length; i++)
      s = s.split("{" + (i + 1) + "}").join(vals[i]);
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
          colNames = colOrder(spec),
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

    // Default display for missing (null/NA) cells: an em dash unless spec.missing
    // overrides it (set to "" to keep them blank). A per-column lt_sub(missing=)
    // has already filled its cells above, so only still-empty null cells get the
    // default; empty strings in the data stay empty.
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
          // Run fn on each op of the given type, in document order.
          onOp = (t, fn) => { for (const op of ops) if (op.type === t) fn(op); };

    // row_group: array → rowspan mode; string → separator-row mode
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

    // Explicit spanners: reorder each spanner's columns to match the final
    // (post-move) body order, so a spanner is recorded/rendered correctly
    // regardless of the order in which its columns were listed. A spanner is
    // matched to the visual position of its first column and then spans the
    // next columns.length cells, so a first column that is not the leftmost in
    // `visible` would otherwise misalign the header row.
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

    // Inline-graphics cells: an op whose type has a renderer registered on
    // LT.cells (shipped by lt-plot.js) draws its value column as inline SVG
    // (e.g. an error bar). The renderer maps the op to a per-column config
    // here; pushRow and the footer consult cellMap[col] = { rnd, cfg }. Keeping
    // the drawing in a module leaves core with no plot-specific code.
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
          { visible: cols, align, colLabels, colWidths, tableWidth, indent,
            groups, rowSpans, styles, spanners, cellMap, footnotes: fns, notes, header: hdr } = resolveSpec(spec),
          // Core helpers passed to a cell renderer (see LT.cells / lt-plot.js).
          U = { esc, isNum, str },
          reg = indexFootnotes(fns),
          fIdx = matcher(fns, reg.idx),
          nGrp = rowSpans.length,
          nCol = cols.length + nGrp,
          // Whether column `c`'s body cells are raw HTML (see lt_html() on the
          // R side); spec.html_cols is true (all columns) or a name array.
          isRaw = c => rawCol(spec.html_cols, c),
          out = [`<table class="lt-table"${tableWidth ? ` style="width:${tableWidth}"` : ""}>`];
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
    for (const rs of rowSpans)
      out.push(`<th scope="col" class="lt-row-group">${txt(rs.label)}</th>`);
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
    const pushRow = (r, spanCells) => {
      out.push(`<tr>`);
      // Row-group cells. For a group spanning n > 1 rows, the label goes in a
      // non-spanning cell on the first row — so vertical-align centers it
      // within that row's height (matching the body cells) instead of across
      // the whole span — followed by an empty filler cell spanning the
      // remaining n - 1 rows. A single-row group is just the label cell. The
      // per-column descriptor ({label, open} for the label cell, {fill} for the
      // filler, nothing when covered by a filler above) is supplied by the
      // caller when rows are reordered (`spanCells`, computed in view order),
      // else derived from the file-order spans.
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
          // A plot cell: the renderer supplies the inner SVG and may add a <td>
          // class (e.g. to zero padding so a gridline background runs unbroken).
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

    // A separator row-group header: a single full-width cell carrying the label.
    const groupHeader = (label, raw) =>
      `<tr class="lt-row-group"><th colspan="${nCol}" scope="colgroup">${escIf(raw, label)}${mark("row_groups", label)}</th></tr>`;

    // Rowspan group cells recomputed for a reordered view: the file-order
    // `rs.spans` no longer describe the runs, so walk the view sequence and
    // group its rows into runs sharing the same group-value prefix (column gi's
    // run breaks when its value or any earlier group column's value changes).
    // Each run's first row gets the label cell, its second a filler spanning the
    // rest; the remaining rows get nothing. Returns one descriptor array per
    // view position, matching pushRow's `spanCells`.
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

    // <tbody>. An optional `spec._viewRows` sets the order/subset of rows — the
    // seam the interactive plugin uses to sort/filter without re-implementing row
    // rendering. Each entry is a 1-based original row index, or (for a grouped
    // table) an object `{label, raw}` for a separator group header the plugin
    // decided to re-emit. It takes precedence over the file-order branches below,
    // which draw the static table. Row-indexed styles/footnotes/indent stay
    // correct because they remain keyed to the original indices. In rowspan mode
    // the span cells are recomputed from the view order (viewRowSpans).
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
      for (const g of groups) {
        out.push(groupHeader(g.label, g.raw));
        for (const r of g.rows) { seen[r] = 1; pushRow(r); }
      }
      for (let r = 1; r <= nRow; r++) if (!seen[r]) pushRow(r);
    } else {
      for (let r = 1; r <= nRow; r++) pushRow(r);
    }
    out.push(`</tbody>`);

    // <tfoot>: an optional plot-footer row (e.g. a shared error-bar axis), then
    // footnotes and source notes. The footer row carries a per-column cell so
    // each renderer's footer SVG lines up under its plot column; the footnote/
    // note rows span the full width.
    const footCells = cols.map(c =>
      cellMap[c] ? (cellMap[c].rnd.foot?.(cellMap[c].cfg, U) || "") : "");
    const hasFoot = footCells.some(h => h);
    if (reg.order.length || notes.length || hasFoot) {
      const footRow = (cls, html) => `<tr class="${cls}"><td colspan="${nCol}">${html}</td></tr>`;
      out.push(`<tfoot class="lt-footer">`);
      if (hasFoot) {
        out.push(`<tr class="lt-plot-foot">`);
        out.push(`<td></td>`.repeat(nGrp));
        for (let i = 0; i < cols.length; i++) {
          const cm = cellMap[cols[i]];
          // reuse the renderer's cell class so the footer lines up with the plot
          const extra = footCells[i] && cm ? (cm.rnd.cellClass?.(cm.cfg) || "") : "";
          const ac = [colCls[i], extra].filter(Boolean).join(" ");
          out.push(`<td${attr("class", ac)}>${footCells[i]}</td>`);
        }
        out.push(`</tr>`);
      }
      reg.order.forEach((t, i) => out.push(footRow("lt-footnote", `${sup(i + 1)} ${txt(t)}`)));
      for (const n of notes) out.push(footRow("lt-source-note", txt(n)));
      out.push(`</tfoot>`);
    }

    out.push(`</table>`);
    // Expose the resolved visible column order (after hide/move) so plugins can
    // sort/filter without re-deriving it. Set as a side effect, never read by
    // core; harmless for the static/Node render path.
    spec._cols = cols;
    // Also expose the formatted cell text (every column, including hidden ones),
    // so plugins can show the displayed values (e.g. a row detail).
    spec._display = display;
    // Expose the resolved row structure so the interactive plugin can honor it:
    // the separator row groups (each `{label, rows, raw}`), the per-row indent
    // levels (an array, or null when none), and the rowspan group columns (the
    // column names drawn as spanning cells, outermost first, or null) — the
    // plugin sorts/filters within each run and recomputes the spans in view
    // order (see buildHtml's viewRowSpans).
    spec._groups = groups.length ? groups : null;
    spec._indent = indent.some(v => v) ? indent : null;
    spec._rowspan = rowSpans.length ? rowSpans.map(rs => rs.col) : null;
    // Wrap in a div so a wide table can scroll horizontally (`overflow-x`)
    // instead of overflowing the page.
    return `<div class="lt-wrap">${out.join("")}</div>`;
  }

  // Plugin seam (see lt-interactive.js): a plugin attaches its handle under
  // LT.plugins and pushes a callback onto LT.onMount, which core calls with
  // each table element and its spec right after the table is mounted.
  // Cell-renderer seam (see lt-plot.js): a module registers an inline-graphics
  // renderer under LT.cells, keyed by op type, which core consults *during*
  // buildHtml (not post-mount) to draw a column's cells and an optional footer.
  const plugins = root.LT?.plugins || {}, onMount = root.LT?.onMount || [];

  // Alt-click toggles raw values in this table; alt-dblclick toggles page-wide.
  // The handlers must not *return* false (a false return from a DOM0 handler
  // cancels the click's default action — which would, e.g., stop a checkbox
  // inside the table from toggling), so they use statement bodies.
  const wireRaw = tbl => {
    const raw = (e, el) => { if (e.altKey) el.classList.toggle("lt-raw"); };
    tbl.onclick = e => { if (e.detail === 1) raw(e, tbl); };
    tbl.ondblclick = e => { raw(e, tbl.ownerDocument.documentElement); };
  };

  // Finish a freshly inserted table: remember its spec, wire the raw-value
  // toggle, and let the plugins enhance it. Returns the table element.
  const ready = (tbl, spec) => {
    // Stash the spec so a plugin loaded *after* this table mounted (the usual
    // case — core drains the queue before a plugin file runs) can still find
    // and enhance it by scanning `.lt-table`.
    tbl._ltSpec = spec;
    wireRaw(tbl);
    onMount.forEach(f => f(tbl, spec));
    return tbl;
  };

  const mount = (s, spec) => {
    s.insertAdjacentHTML("afterend", buildHtml(spec));
    ready($(s.nextElementSibling, "table"), spec);
  };

  // Render a spec into `el` (replacing its content) at any time, e.g. long
  // after the page loaded, for a table built on demand. Unlike build(), it
  // needs no inline <script> to anchor to, and the caller may hold on to the
  // returned table element.
  const render = (el, spec) => {
    el.innerHTML = buildHtml(spec);
    return ready($(el, "table"), spec);
  };
  // Rebuild an already-mounted table in place from its stashed spec. Used by a
  // cell module (lt-plot.js) that loads *after* core has built a table (e.g. a
  // litedown/knitr doc where an earlier plain table pulled in lt.js first): the
  // module registers its renderer, then refreshes the tables that needed it.
  const refresh = tbl => {
    const spec = tbl?._ltSpec, wrap = tbl?.closest(".lt-wrap");
    if (!spec || !wrap) return;
    wrap.insertAdjacentHTML("afterend", buildHtml(spec));
    const next = wrap.nextElementSibling;
    wrap.remove();
    return ready($(next, "table"), spec);
  };
  // q.push renders immediately; replay any entries queued before we loaded.
  const q = { push: e => mount(e.s, e.d) };
  (root.LT?.q || []).forEach(q.push);
  root.LT = {
    build: spec => mount(document.currentScript, spec),
    render, refresh, buildHtml, plugins, onMount, cells: cellRenderers, q,
  };
})(window);
