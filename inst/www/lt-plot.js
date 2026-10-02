/* lt-plot.js — inline graphics cells for lt tables (error bars, sparklines, …).
 * Registers cell renderers on LT.cells; the core runtime (lt.js) consults them
 * while building the <table>, so a plot draws for every render path (static,
 * Node-baked, and the interactive per-page rebuild) with no plot code in core.
 * This file must run before lt.js: core reads LT.cells when it drains the queue
 * (linked <script defer> keeps document order; inline scripts run in order too).
 */
(root => {
  "use strict";
  const LT = root.LT || (root.LT = {});
  const cells = LT.cells || (LT.cells = {});
  if (cells.errorbar) return;  // duplicate inclusion is a no-op

  // Horizontal padding (px) left/right inside an error-bar SVG, so points,
  // bars, and axis ticks never sit flush against the cell edge.
  const EB_PAD = 4;
  // Axis tick-label font size (px); also drives how many ticks fit (see below)
  // and must match the font-size for `.lt-eb-axis text` in lt-plot.css.
  const EB_AXIS_FONT = 11;

  // "Nice" axis ticks for [lo, hi] (~n of them), à la base R's pretty(): snap
  // the step to 1/2/5 × 10^k so labels are round numbers. Returns tick values
  // rounded to the step's own precision (so no float noise like 0.30000001).
  function niceTicks(lo, hi, n = 5) {
    if (!(hi > lo)) return [lo];
    const niceNum = (x, round) => {
      const e = Math.floor(Math.log10(x)), f = x / 10 ** e,
            nf = round ? (f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10)
                       : (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10);
      return nf * 10 ** e;
    };
    const d = niceNum(niceNum(hi - lo, false) / (n - 1), true),
          dec = Math.max(0, -Math.floor(Math.log10(d))), ticks = [];
    for (let v = Math.ceil(lo / d) * d; v <= hi + d / 2; v += d)
      ticks.push(+v.toFixed(dec));
    return ticks;
  }

  // How many axis ticks fit without the labels crowding: budget each label at
  // ~0.6em per char (its widest value is at one of the ends) plus a one-em gap.
  function nAxisTicks(eb) {
    const inner = eb.width - 2 * EB_PAD,
          chars = Math.max(String(eb.min).length, String(eb.max).length),
          per = chars * EB_AXIS_FONT * 0.6 + EB_AXIS_FONT;
    return Math.max(2, Math.min(8, Math.floor(inner / per) + 1));
  }
  // Map a value to an x pixel on an error-bar's shared [min,max] scale: fit the
  // scale into [EB_PAD, W - EB_PAD], clamp into that range (a degenerate scale
  // centers), and round to 0.1px so coords stay short and free of float noise.
  const ebX = (eb, v) => {
    const inner = eb.width - 2 * EB_PAD, span = eb.max - eb.min,
          p = span > 0 ? EB_PAD + (v - eb.min) / span * inner : eb.width / 2;
    return Math.round(Math.max(EB_PAD, Math.min(eb.width - EB_PAD, p)) * 10) / 10;
  };

  // Inline SVG for an error-bar cell: a point at the estimate and a horizontal
  // bar (with end caps) from the lower to the upper bound, on the column's
  // shared [min,max] scale. Only the numbers are shipped in the spec; the SVG
  // is built here at render time, so an interactive table (which rebuilds
  // <tbody> from spec._viewRows) draws it only for the rows on the current
  // page. `u` carries the core helpers (esc/isNum/str) passed in by lt.js.
  function svgErrorbar(eb, data, r, u) {
    const num = k => { const v = data[k]?.[r - 1]; return u.isNum(v) ? v : null; };
    const est = num(eb.col), lo = num(eb.lo), hi = num(eb.hi);
    if (est == null && lo == null && hi == null) return "";
    const H = eb.height, y = H / 2, x = v => ebX(eb, v),
          cap = Math.min(4, (H - 1) / 2);  // half-height of the end caps
    let s = `<svg class="lt-eb" width="${eb.width}" height="${H}">`;
    if (eb.ref != null)
      s += `<line class="lt-eb-ref" x1="${x(eb.ref)}" y1="0" x2="${x(eb.ref)}" y2="${H}"/>`;
    if (lo != null && hi != null) {
      // horizontal bar plus short vertical end caps at both ends
      const xl = x(lo), xh = x(hi);
      s += `<line x1="${xl}" y1="${y}" x2="${xh}" y2="${y}"/>` +
           `<line x1="${xl}" y1="${y - cap}" x2="${xl}" y2="${y + cap}"/>` +
           `<line x1="${xh}" y1="${y - cap}" x2="${xh}" y2="${y + cap}"/>`;
    }
    if (est != null) s += `<circle cx="${x(est)}" cy="${y}" r="3"/>`;
    const ci = lo != null && hi != null ? ` (${u.str(lo)}, ${u.str(hi)})` : "";
    s += `<title>${u.esc((est != null ? u.str(est) : "") + ci)}</title></svg>`;
    return s;
  }

  // Full-cell background layer of faint vertical gridlines at the shared tick
  // positions. Its width is fixed in px (matching the plot SVG, so the lines
  // stay aligned with the bars), while height="100%" + preserveAspectRatio
  // "none" stretch it to fill the whole <td> vertically — so the lines run
  // continuously across the cell's (zeroed) padding and line up row-to-row. A
  // per-cell fixed-height SVG could not: the cell padding leaves a gap it can't
  // reach. Scaling only the vertical axis is harmless for vertical lines.
  function svgGrid(eb) {
    let s = `<svg class="lt-eb-grid-bg" width="${eb.width}" height="100%" ` +
            `viewBox="0 0 ${eb.width} 10" preserveAspectRatio="none">`;
    for (const t of eb.ticks)
      s += `<line x1="${ebX(eb, t)}" y1="0" x2="${ebX(eb, t)}" y2="10"/>`;
    return s + `</svg>`;
  }

  // A shared horizontal axis for an error-bar column, drawn once in the footer:
  // a baseline with a tick mark + label at each nice tick (eb.ticks), and an
  // optional caption (eb.axisLabel) centered below. `overflow="visible"` lets a
  // caption slightly wider than the narrow column spill rather than clip.
  function svgAxis(eb, u) {
    const W = eb.width, lbl = eb.axisLabel, H = lbl ? 32 : 18, x = v => ebX(eb, v);
    let s = `<svg class="lt-eb-axis" width="${W}" height="${H}" overflow="visible">` +
            `<line x1="${EB_PAD}" y1="1" x2="${W - EB_PAD}" y2="1"/>`;
    for (const t of (eb.ticks || [])) {
      const xt = x(t),
            anchor = xt <= EB_PAD ? "start" : xt >= W - EB_PAD ? "end" : "middle";
      s += `<line x1="${xt}" y1="0" x2="${xt}" y2="4"/>` +
           `<text x="${xt}" y="15" text-anchor="${anchor}">${u.esc(u.str(t))}</text>`;
    }
    if (lbl)
      s += `<text class="lt-eb-axis-label" x="${W / 2}" y="${H - 4}" text-anchor="middle">${u.esc(lbl)}</text>`;
    return s + `</svg>`;
  }

  // Error-bar cell renderer. columns = [value, lower, upper]; the plot replaces
  // the value column's cells on a scale shared across the column. A renderer is
  // an object with: resolve(op) -> { col: config } (the per-column setup, run
  // once in resolveSpec); cellClass(cfg) -> extra <td> class; cell(cfg, data,
  // r, u) -> body-cell HTML; foot(cfg, u) -> footer (axis) HTML or "".
  cells.errorbar = {
    resolve(op) {
      const [v, lo, hi] = op.columns || [];
      if (!v) return {};
      const eb = {
        col: v, lo, hi, min: op.min, max: op.max, ref: op.ref, axis: op.axis,
        axisLabel: op.axis_label, width: op.width || 160, height: op.height || 16
      };
      // When an axis is requested, the same nice ticks drive both the footer
      // axis and the faint in-cell gridlines; their count is capped so the
      // labels do not crowd at the given width.
      if (op.axis) eb.ticks = niceTicks(eb.min, eb.max, nAxisTicks(eb));
      return { [v]: eb };
    },
    // lt-eb-cell zeroes the cell's vertical padding so the stretched gridline
    // background can run unbroken from one row to the next.
    cellClass: eb => eb.ticks ? "lt-eb-cell" : "",
    cell: (eb, data, r, u) => (eb.ticks ? svgGrid(eb) : "") + svgErrorbar(eb, data, r, u),
    foot: (eb, u) => eb.axis ? svgAxis(eb, u) : ""
  };

  // If core already built a table before this module loaded (a doc where an
  // earlier plain table pulled in lt.js first, so its renderer was missing),
  // re-render any mounted table that uses a renderer we just registered. Tables
  // mounted after us need no help — the renderer is already in place. No-op
  // when nothing is mounted yet (we loaded first) or outside a browser (the
  // Node bake controls load order).
  const doc = root.document;
  if (doc) for (const tbl of doc.querySelectorAll(".lt-table")) {
    if ((tbl._ltSpec?.ops || []).some(o => cells[o.type])) LT.refresh?.(tbl);
  }
})(window);
