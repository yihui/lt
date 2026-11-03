/* lt-plot.js — inline graphics cells for lt tables (error bars, sparklines,
 * dot plots, …).
 * Registers cell renderers on LT.cells; core (lt.js) consults them while
 * building the <table>, so plots draw on every render path (static,
 * Node-baked, interactive rebuild) with no plot code in core.
 * Must run before lt.js: core reads LT.cells when draining the queue (linked
 * <script defer> keeps document order; inline scripts run in order too).
 */
(root => {
  "use strict";
  const LT = root.LT || (root.LT = {}), cells = LT.cells || (LT.cells = {});
  if (cells.errorbar) return;  // duplicate include: no-op

  // Horizontal padding (px) inside an error-bar SVG, so points, bars, axis
  // ticks never touch the cell edge.
  const EB_PAD = 4;
  // Axis tick-label font size (px); also sets how many ticks fit (below).
  // Must match `.lt-eb-axis text` font-size in lt-plot.css.
  const EB_AXIS_FONT = 11;

  // Auto-fit: cfg.fit = CSS width (--fw), cfg.floor = min px (--w). Resizer
  // (bottom) remeasures and redraws at real px, keeping marks crisp.
  const fitCls = cfg => cfg.fit ? " lt-fit" : "",
        fitDecl = cfg => cfg.fit ? `--w:${cfg.floor}px;--fw:${cfg.fit}` : "",
        fitStyle = cfg => cfg.fit ? ` style="${fitDecl(cfg)}"` : "";
  // Shared cfg fields: coord width (op._w once resizer measured, else
  // fixed/floor px `dflt`), CSS width, floor.
  const fitCfg = (op, dflt) => {
    const floor = op.width || dflt;
    return { width: op._w || floor, fit: op.fit, floor };
  };

  // "Nice" axis ticks for [lo, hi] (~n), like base R pretty(): step snapped
  // to 1/2/5 x 10^k. Returns values rounded to step precision (no float noise
  // like 0.30000001).
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
    // Stay within [lo, hi]: tick past hi would clamp onto right edge (see
    // ebX), bunching last gap. Small tolerance absorbs float drift when
    // landing exactly on hi.
    for (let v = Math.ceil(lo / d) * d; v <= hi + d * 1e-9; v += d)
      ticks.push(+v.toFixed(dec));
    return ticks;
  }

  // Ticks that fit without crowding: each label ~0.6em per char (widest value
  // at an end) plus one-em gap.
  function nAxisTicks(eb) {
    const inner = eb.width - 2 * EB_PAD,
          chars = Math.max(String(eb.min).length, String(eb.max).length),
          per = chars * EB_AXIS_FONT * 0.6 + EB_AXIS_FONT;
    return Math.max(2, Math.min(8, Math.floor(inner / per) + 1));
  }
  // Value -> x pixel on error-bar shared [min,max] scale: fit into [EB_PAD, W
  // - EB_PAD], clamp (degenerate scale centers), round to 0.1px for short
  // coords.
  const ebX = (eb, v) => {
    const inner = eb.width - 2 * EB_PAD, span = eb.max - eb.min,
          p = span > 0 ? EB_PAD + (v - eb.min) / span * inner : eb.width / 2;
    return Math.round(Math.max(EB_PAD, Math.min(eb.width - EB_PAD, p)) * 10) / 10;
  };

  // y pixel of series i of n in cell height H: lone series on mid-line, else
  // evenly spaced tracks so stacked marks do not overlap. Shared by stacked
  // error bar and staggered dot plot.
  const stackY = (i, n, H) => n <= 1 ? H / 2 : Math.round((i + 1) / (n + 1) * H);

  // Inline SVG for error-bar cell: one series per triple (value, lower,
  // upper): point at estimate plus horizontal bar (end caps) lower to upper,
  // on column shared [min,max] scale. Single series on mid-line; several
  // stack at evenly spaced rows, optionally colored (see footer legend). Spec
  // ships only numbers; SVG built at render time, so interactive tables
  // (rebuilding <tbody> from spec._viewRows) draw only current-page rows. `u`
  // = core helpers (esc/isNum/str) from lt.js.
  function svgErrorbar(eb, data, r, u) {
    const num = k => { const v = data[k]?.[r - 1]; return u.isNum(v) ? v : null; };
    const H = eb.height, n = eb.cols.length, x = v => ebX(eb, v),
          yOf = i => stackY(i, n, H),  // one track per series, stacked
          cap = Math.min(3, (H / n - 1) / 2);  // half-height of the end caps
    let s = `<svg class="lt-eb${fitCls(eb)}" width="${eb.width}" height="${H}"${fitStyle(eb)}>`;
    if (eb.ref != null)
      s += `<line class="lt-eb-ref" x1="${x(eb.ref)}" y1="0" x2="${x(eb.ref)}" y2="${H}"/>`;
    const titles = [];
    eb.cols.forEach((c, i) => {
      const est = num(c), lo = num(eb.los[i]), hi = num(eb.his[i]);
      if (est == null && lo == null && hi == null) return;
      const y = yOf(i), col = eb.colors?.[i],
            // per-series color via stroke=/fill= attributes;
            // stylesheet only defaults series lacking them
            // (:not([stroke])/:not([fill])), so color shows but
            // user CSS can override
            st = col ? ` stroke="${u.esc(col)}"` : "",
            fl = col ? ` fill="${u.esc(col)}"` : "";
      if (lo != null && hi != null) {
        // horizontal bar plus short vertical end caps
        const xl = x(lo), xh = x(hi);
        s += `<line${st} x1="${xl}" y1="${y}" x2="${xh}" y2="${y}"/>` +
             `<line${st} x1="${xl}" y1="${y - cap}" x2="${xl}" y2="${y + cap}"/>` +
             `<line${st} x1="${xh}" y1="${y - cap}" x2="${xh}" y2="${y + cap}"/>`;
      }
      if (est != null) s += `<circle${fl} cx="${x(est)}" cy="${y}" r="3"/>`;
      const ci = lo != null && hi != null ? ` (${u.str(lo)}, ${u.str(hi)})` : "";
      titles.push((eb.labels?.[i] ? eb.labels[i] + ": " : "") +
                  (est != null ? u.str(est) : "") + ci);
    });
    if (!titles.length) return "";
    return s + `<title>${u.esc(titles.join("\n"))}</title></svg>`;
  }

  // Full-cell background of faint vertical gridlines at shared tick
  // positions. Width fixed in px (matches plot SVG, so lines align with
  // bars); height="100%" + preserveAspectRatio "none" stretches it over the
  // whole <td>, so lines run continuously across zeroed padding and line up
  // row-to-row. Per-cell fixed-height SVG could not reach the padding.
  // Vertical-only scaling is harmless for vertical lines.
  function svgGrid(eb) {
    let s = `<svg class="lt-eb-grid-bg${fitCls(eb)}" width="${eb.width}" height="100%" ` +
            `viewBox="0 0 ${eb.width} 10" preserveAspectRatio="none">`;
    for (const t of eb.ticks)
      s += `<line x1="${ebX(eb, t)}" y1="0" x2="${ebX(eb, t)}" y2="10"/>`;
    return s + `</svg>`;
  }

  // Shared horizontal axis for error-bar column, drawn once in footer:
  // baseline, tick mark + label per nice tick (eb.ticks), optional centered
  // caption (eb.axisLabel) below. `overflow="visible"` lets a caption wider
  // than the column spill, not clip.
  function svgAxis(eb, u) {
    const W = eb.width, lbl = eb.axisLabel, H = lbl ? 32 : 18, x = v => ebX(eb, v);
    let s = `<svg class="lt-eb-axis${fitCls(eb)}" width="${W}" height="${H}" overflow="visible"${fitStyle(eb)}>` +
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

  // Build axis-capable plot renderer (error bar, dot plot) from per-cell SVG
  // drawer, their only difference. Draws into `into` column (or first of
  // `columns`) on scale shared across column; `extra(op)` adds
  // renderer-specific config (bounds for error bar, stagger for dot plot).
  const axisPlot = (extra, draw) => ({
    resolve(op) {
      const cols = op.columns || [], v = op.into || cols[0];
      if (!v || !cols.length) return {};
      const cfg = {
        col: v, cols, colors: op.colors, labels: op.labels,
        min: op.min, max: op.max, axisLabel: op.axis_label,
        height: op.height || 16, ...fitCfg(op, 160), ...extra(op)
      };
      // With axis: same nice ticks drive footer axis and in-cell
      // gridlines; count capped so labels do not crowd at given width.
      if (op.axis) cfg.ticks = niceTicks(cfg.min, cfg.max, nAxisTicks(cfg));
      return { [v]: cfg };
    },
    // lt-eb-cell zeroes cell vertical padding so stretched gridline
    // background runs unbroken between rows.
    cellClass: cfg => cfg.ticks ? "lt-eb-cell" : "",
    cell: (cfg, data, r, u) => (cfg.ticks ? svgGrid(cfg) : "") + draw(cfg, data, r, u),
    foot: (cfg, u) => (cfg.ticks ? svgAxis(cfg, u) : "") + legend(cfg, u)
  });

  // Error-bar renderer. columns = [value, lower, upper] per series; draws
  // point-and-bar per series on column shared scale.
  cells.errorbar = axisPlot(
    op => ({ los: op.lowers || [], his: op.uppers || [], ref: op.ref }),
    svgErrorbar
  );

  // Padding (px) inside sparkline SVG, so line/bars never touch the edge.
  const SP_PAD = 2;
  const round1 = n => Math.round(n * 10) / 10;  // 0.1px, to keep coords short
  const q = v => `"${v}"`;  // double-quote an SVG attribute value

  // Row series for sparkline: single named column whose cell is an array
  // (list-column) -> that array; else each named column gives one point, read
  // left to right. Non-finite -> null (line gap, skipped bar). `u` = core
  // helpers (esc/isNum/str).
  function spSeries(sp, data, r, u) {
    const cell = data[sp.cols[0]]?.[r - 1],
          raw = sp.cols.length === 1 && Array.isArray(cell)
            ? cell : sp.cols.map(c => data[c]?.[r - 1]);
    return raw.map(v => u.isNum(v) ? +v : null);
  }

  // Inline SVG sparkline (line or bar). Scaled to shared [min,max] if spec
  // gives one, else row own finite range; flat series on mid-line. Points
  // evenly spaced across width. Nulls break line into subpaths (drop bars).
  function svgSparkline(sp, data, r, u) {
    const vals = spSeries(sp, data, r, u), fin = vals.filter(v => v != null);
    if (!fin.length) return "";
    const W = sp.width, H = sp.height, n = vals.length,
          lo = sp.min != null ? sp.min : Math.min(...fin),
          hi = sp.max != null ? sp.max : Math.max(...fin);
    const xAt = i => round1(n > 1 ? SP_PAD + i / (n - 1) * (W - 2 * SP_PAD) : W / 2),
          yAt = v => round1(hi > lo
            ? H - SP_PAD - (v - lo) / (hi - lo) * (H - 2 * SP_PAD) : H / 2);
    // line/bars inherit `currentColor`: one color prop styles either
    const sv = [fitDecl(sp), sp.color && `color:${u.esc(sp.color)}`]
      .filter(Boolean).join(";");
    const style = sv ? ` style="${sv}"` : "";
    let body;
    if (sp.kind === "bar") {
      // one equal-width slot per value; bar centered in slot, grows from
      // zero baseline when scale straddles 0, else bottom.
      const slot = (W - 2 * SP_PAD) / n, bw = round1(Math.max(1, slot * 0.8)),
            base = yAt(lo < 0 && hi > 0 ? 0 : lo);
      body = vals.map((v, i) => {
        if (v == null) return "";
        const yv = yAt(v), x = round1(SP_PAD + i * slot + (slot - bw) / 2);
        return `<rect class="lt-spark-bar" x=${q(x)} y=${q(Math.min(yv, base))} ` +
               `width=${q(bw)} height=${q(Math.max(1, Math.abs(base - yv)))}/>`;
      }).join("");
    } else {
      let d = "", pen = false;
      vals.forEach((v, i) => {
        if (v == null) { pen = false; return; }
        d += `${pen ? "L" : "M"}${xAt(i)} ${yAt(v)}`;
        pen = true;
      });
      body = `<path class="lt-spark-line" d="${d}"/>`;
    }
    return `<svg class="lt-spark${fitCls(sp)}" width="${W}" height="${H}"${style}>${body}` +
           `<title>${u.esc(fin.map(u.str).join(", "))}</title></svg>`;
  }

  // Sparkline renderer. columns = one list-column, or several numeric columns
  // read across row; drawn in first column cells.
  cells.sparkline = {
    resolve(op) {
      const cols = op.columns || [], v = cols[0];
      if (!v) return {};
      return { [v]: {
        col: v, cols, kind: op.kind, min: op.min, max: op.max, color: op.color,
        height: op.height || 20, ...fitCfg(op, 120)
      } };
    },
    cell: (sp, data, r, u) => svgSparkline(sp, data, r, u)
  };

  // Inline SVG dot plot for cell: one dot per column at its value on
  // column-group shared [min,max] scale, so N columns show N dots
  // horizontally on one baseline. Colors, if given, per column (see
  // legend()). Non-finite draws no dot. Reuses error-bar scale (ebX) and
  // padding.
  function svgDotplot(dp, data, r, u) {
    const H = dp.height, n = dp.cols.length, x = v => ebX(dp, v),
          // dots on mid-line by default; stagger gives each column
          // own track (like stacked error bar) so near-equal values
          // do not overlap; vertical position is cosmetic, only x
          // carries a value
          yOf = i => dp.stagger ? stackY(i, n, H) : H / 2;
    let s = `<svg class="lt-dot${fitCls(dp)}" width="${dp.width}" height="${H}"${fitStyle(dp)}>`;
    const titles = [];
    dp.cols.forEach((c, i) => {
      const v = data[c]?.[r - 1];
      if (!u.isNum(v)) return;
      // per-column color is a fill= attribute; stylesheet only defaults
      // dots lacking it (:not([fill])), so color shows but user CSS can
      // override
      const col = dp.colors?.[i], fl = col ? ` fill="${u.esc(col)}"` : "";
      s += `<circle${fl} cx="${x(v)}" cy="${yOf(i)}" r="3"/>`;
      titles.push((dp.labels?.[i] ? dp.labels[i] + ": " : "") + u.str(v));
    });
    return s + `<title>${u.esc(titles.join("\n"))}</title></svg>`;
  }

  // Color key for colored dot/error-bar plot, drawn once in footer under
  // axis: swatch + label per series. "" if monochrome. Shared by dot-plot and
  // error-bar renderers (cfg.cols/colors/labels same shape).
  function legend(cfg, u) {
    if (!cfg.colors) return "";
    const items = cfg.cols.map((c, i) =>
      `<span><i style="background:${u.esc(cfg.colors[i])}"></i>` +
      `${u.esc(cfg.labels?.[i] ?? c)}</span>`).join("");
    return `<div class="lt-plot-legend">${items}</div>`;
  }

  // Dot-plot renderer. columns = value columns (one dot each); draws on scale
  // shared across them. Shares error-bar axis/gridline machinery via axisPlot
  // (ticks, svgGrid, svgAxis, lt-eb-cell, legend).
  cells.dotplot = axisPlot(op => ({ stagger: op.stagger }), svgDotplot);

  // Resizer for fit plots: on each width change of a fit column, store new px
  // on op (op._w) and redraw. Observes column header cell (core gives one per
  // column in tbl._ltHead): <thead> survives <tbody> swaps of
  // sort/filter/paging and changes exactly when column does (resize drag,
  // hidden column, reflow), unlike wrapper. Draw at plot SVG own width:
  // width:100% reports px it fills, no intrinsic width, so redraw never
  // resizes the measured column (no loop). Redraws coalesce per frame;
  // refresh(false) keeps view and page.
  (LT.onMount || (LT.onMount = [])).push((tbl, spec) => {
    const fitOps = (spec.ops || []).filter(o => cells[o.type] && o.fit);
    if (!fitOps.length || !root.ResizeObserver || !tbl._ltHead) return;
    const redraw = () => (tbl._lt ? tbl._lt.refresh(false) : LT.refresh(tbl));
    let raf;
    const probes = fitOps  // [op, header cell], fit columns core knows
      .map(op => [op, tbl._ltHead[op.into || op.columns?.[0]]])
      .filter(([, th]) => th);
    const measure = () => {
      let changed = false;
      for (const [op, th] of probes) {
        const svg = tbl.querySelector("tbody tr:not(.lt-row-group)")
          ?.cells[th.cellIndex]?.querySelector("svg");
        if (!svg) continue;
        const w = Math.round(svg.getBoundingClientRect().width);
        if (w > 0 && w !== op._w) { op._w = w; changed = true; }
      }
      if (changed) { cancelAnimationFrame(raf); raf = requestAnimationFrame(redraw); }
    };
    const ro = new ResizeObserver(measure);
    for (const [, th] of probes) ro.observe(th);
    measure();  // deterministic initial fit; observer handles later changes
  });

  // If core built a table before this module loaded (e.g. earlier plain table
  // pulled in lt.js first, so renderer was missing), re-render mounted tables
  // using a renderer just registered. Tables mounted later need no help.
  // No-op when nothing mounted yet (we loaded first) or outside a browser
  // (Node bake controls load order).
  const doc = root.document;
  if (doc) for (const tbl of doc.querySelectorAll(".lt-table")) {
    if ((tbl._ltSpec?.ops || []).some(o => cells[o.type])) LT.refresh?.(tbl);
  }
})(window);
