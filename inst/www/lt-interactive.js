/* lt-interactive.js — opt-in interactivity for lt tables (search, sort, column
 * filters, pagination, column resize, column show/hide).
 *
 * Plugin on the LT global (see lt.js); no new global. For a spec with
 * `interactive`, adds controls and re-renders <tbody> via core `spec._viewRows`.
 * Controls are table rows (search in <thead>, pager in <tfoot>), so they match
 * table width and scroll with it. Separator groups, indentation, and rowspan
 * groups sort/filter within their group or subtree, never across (see
 * computeView).
 */
(root => {
  "use strict";
  const LT = root.LT;
  // Bail if core is absent/old or plugin already loaded.
  if (!LT?.onMount || LT.plugins.interactive) return;

  const Q = LT.plugins.query,  // plain-language queries (lt-query.js)
        MIN_COL = 24;  // px: min dragged column width
  let coll;  // lazy locale-aware comparator
  // Numeric if first non-null value is a number (same rule as core lt.js).
  // Subscript digits (₁ ₂ …) for sort-order ordinals.
  const sub = n => String(n).replace(/\d/g, d => "₀₁₂₃₄₅₆₇₈₉"[d]);
  // Sort key `"col"`, `"-col"` (desc), or `{col, dir}` -> `{col, dir}`.
  const parseKey = k => typeof k !== "string" ? { ...k } :
    k[0] === "-" ? { col: k.slice(1), dir: "desc" } : { col: k, dir: "asc" };
  // Compare non-null values: subtraction if numeric, else locale string compare.
  const cmpVals = (x, y, num) => {
    coll ||= new Intl.Collator();
    return num ? x - y : coll.compare(String(x), String(y));
  };

  // --- Small DOM helpers ---
  const { $, $$, on, off, numCol, dateFmt } = LT;
  // Columns as sort/filter see them: date-time columns become their displayed
  // text, as do R dates (already "YYYY-MM-DD"), so `x >= "2024-01-05"` works and
  // text order is time order. Such arrays are flagged `date`; the raw
  // `spec.data` is untouched. Cached per data object.
  const textual = spec => {
    const d = spec.data || {};
    if (spec._txt?.d !== d) {
      const t = { ...d };
      for (const c in d) {
        const f = dateFmt(d[c]);
        if (f || spec.dates?.includes(c))
          t[c] = Object.assign(d[c].map(v => v == null || !f ? v : f(v)), { date: true });
      }
      spec._txt = { d, t };
    }
    return spec._txt.t;
  };
  // A row's data cells in column order: children minus leading rowspan group
  // cells (`lt-row-group`), which aren't in `spec._cols` and are missing on a
  // run's later rows. Class-based, not positional, so index code stays correct.
  const dataCells = tr =>
    [...tr.children].filter(c => !c.classList.contains("lt-row-group"));
  // A header cell's label nodes: those before the <br> that starts the type tag
  // and filter line (if any)
  const labelNodes = th => {
    const n = [...th.childNodes], i = n.findIndex(e => e.nodeName === "BR");
    return i < 0 ? n : n.slice(0, i);
  };
  // Create <tag> with `props`: dashed key = attribute, else DOM property.
  // Appends to `parent` if given; returns the element.
  function elem(doc, tag, props = {}, parent) {
    const e = doc.createElement(tag);
    for (const k in props)
      k.includes("-") ? e.setAttribute(k, props[k]) : (e[k] = props[k]);
    return parent ? parent.appendChild(e) : e;
  }
  // Pointer drag from pointerdown `e`: `onMove(ev)` per move until pointerup,
  // then `onEnd()`. Used by column resize and slider thumbs; blocks text selection.
  function drag(e, onMove, onEnd) {
    e.preventDefault();
    const doc = e.target.ownerDocument || document, move = ev => onMove(ev);
    on(doc, "pointermove", move);
    on(doc, "pointerup", () => {
      off(doc, "pointermove", move);
      onEnd && onEnd();
    }, { once: true });
  }

  // Compile a search term to a predicate over a row's cells (`{raw, disp}`), or
  // null to keep every row. Ported from forestly's inst/js/search-filter.js for
  // consistent results.
  //  - Expression mode, if the term uses cell variable `x` (`x > 5`): JS run on
  //    the *raw* value, as string and (if finite) number. Leading `!` or `!=` is
  //    negation: keep a row only if *every* cell passes; else *any* match keeps it.
  //  - Otherwise substring mode: case-insensitive match on *display* text; leading
  //    `!` negates.
  function matcher(term) {
    const v = String(term ?? "").trim();
    if (v === "") return null;
    if (/(^|[^\w$])x([^\w$]|$)/.test(v)) {
      let fn;
      try { fn = new Function("x", `return (${v});`); } catch (e) {}
      if (fn) {
        const neg = /^\s*!|!=/.test(v), test = raw => {
          try {
            // missing value is `undefined`: `x == null` matches it, `x > 5` doesn't
            if (raw == null) return neg || !!fn(undefined);
            const num = Number(raw);
            return !!fn(String(raw)) || (raw !== "" && isFinite(num) && !!fn(num));
          } catch (e) { return false; }
        };
        return cells => cells[neg ? "every" : "some"](c => test(c.raw));
      }
    }
    const neg = v[0] === "!", needle = (neg ? v.slice(1).trim() : v).toLowerCase();
    if (needle === "") return null;
    return cells => neg !== cells.some(
      c => c.disp != null && String(c.disp).toLowerCase().includes(needle)
    );
  }

  // View pipeline (pure, no DOM): column filters, table search, external
  // predicates (ANDed), then sort -> 1-based original row indices for
  // `spec._viewRows`. `disp[col][i]` = displayed text (what substring search
  // matches). `state`: `filters[col]` terms, `term` search, `predicates` by id
  // (see el._lt.filter), `sort` = ordered `{col, dir}` keys.
  function computeView(spec, disp, state) {
    const cols = spec._cols || [], data = spec.data || {}, vals = textual(spec),
          nRow = (data[cols[0]] || []).length,
          cell = (c, r) => ({
            raw: vals[c]?.[r - 1] ?? null, disp: disp[c]?.[r - 1] ?? ""
          });

    // Per-row keep test, ANDed; cheap single-cell filters first.
    const tests = [];
    // A query tree (see lt-query.js) -> row test. Leaves run `matcher` on the
    // leaf's column, or on every column (any cell may match) if it has none.
    const compile = n => {
      if (n.op) {
        const fs = n.items.map(compile);
        return n.op === "and" ? r => fs.every(f => f(r)) : r => fs.some(f => f(r));
      }
      const pred = matcher(n.term);
      return !pred ? () => true : n.col != null ? r => pred([cell(n.col, r)]) :
        r => pred(cols.map(c => cell(c, r)));
    };
    // `filters`: a term (widgets) or a tree (column boxes) per column; `where`:
    // the search box's tree
    for (const c in state.filters || {}) {
      const f = state.filters[c];
      tests.push(compile(typeof f === "string" ? { col: c, term: f } : f));
    }
    if (state.where) tests.push(compile(state.where));
    const sPred = matcher(state.term);
    if (sPred) tests.push(r => sPred(cols.map(c => cell(c, r))));
    // External predicates (el._lt.filter) run last, on the row's raw values by
    // column. Row has *every* column, not just visible `cols`, so widgets can
    // filter on hidden helpers (e.g. forestly's `hide_prop`, `parameter`).
    const fns = Object.values(state.predicates || {});
    if (fns.length) {
      const all = Object.keys(data),
            row = r => Object.fromEntries(all.map(c => [c, data[c]?.[r - 1] ?? null]));
      tests.push(r => { const o = row(r); return fns.every(f => f(o)); });
    }
    const keep = r => tests.every(t => t(r));

    // Comparator from sort keys, next key on tie. nulls sort last regardless of
    // direction. Null if nothing to sort.
    const makeCmp = sortKeys => {
      const keys = sortKeys.map(k => {
        const col = vals[k.col];
        return col && { col, num: numCol(col), dir: k.dir === "desc" ? -1 : 1 };
      }).filter(Boolean);
      return keys.length ? (a, b) => {
        for (const { col, num, dir } of keys) {
          const x = col[a - 1], y = col[b - 1], xn = x == null, yn = y == null;
          if (xn || yn) { if (xn !== yn) return xn ? 1 : -1; continue; }
          const c = cmpVals(x, y, num);
          if (c) return dir * c;
        }
        return 0;
      } : null;
    };

    // Rows (document order) -> kept rows in view order, sorted by `cmp`. Without
    // indentation: plain filter + sort. With it, rows form a tree (parent = nearest
    // earlier row one level up): filter keeps rows with a surviving descendant (match
    // stays in context); sort reorders siblings, subtrees move with their parent.
    const indent = spec._indent;
    const reduce = (rows, cmp) => {
      if (!indent) {
        const out = rows.filter(keep);
        return cmp ? out.sort(cmp) : out;
      }
      const roots = [], stack = [];
      for (const r of rows) {
        const node = { r, kids: [] }, lv = indent[r - 1] || 0;
        while (stack.length && stack[stack.length - 1].lv >= lv) stack.pop();
        (stack.length ? stack[stack.length - 1].node.kids : roots).push(node);
        stack.push({ node, lv });
      }
      const prune = ns => ns.map(n => {
        const kids = prune(n.kids);
        return keep(n.r) || kids.length ? { r: n.r, kids } : null;
      }).filter(Boolean);
      const sortNodes = ns => {
        if (cmp) ns.sort((a, b) => cmp(a.r, b.r));
        ns.forEach(n => sortNodes(n.kids));
        return ns;
      };
      const flat = [], walk = ns => ns.forEach(n => { flat.push(n.r); walk(n.kids); });
      walk(sortNodes(prune(roots)));
      return flat;
    };

    const all = () => Array.from({ length: nRow }, (_, i) => i + 1);

    // Rowspan groups nest (outermost first), so data sorting may only reorder
    // within the innermost group, or a spanning cell would split. Partition by
    // group column 1, recurse into column 2 per block, ..., sort by data keys at
    // leaves. A clicked group column orders its blocks (key pulled from leaf
    // sort); else blocks keep first-appearance order. Render recomputes spans.
    const gcols = spec._rowspan;
    if (gcols) {
      const dir = {}, leaf = [];
      for (const k of state.sort || [])
        gcols.includes(k.col) ? (dir[k.col] = k.dir) : leaf.push(k);
      const leafCmp = makeCmp(leaf);
      const partition = (rows, depth) => {
        if (depth === gcols.length) return reduce(rows, leafCmp);
        const col = vals[gcols[depth]], blocks = new Map();
        for (const r of rows) {
          const v = col[r - 1], key = v == null ? "\0" : String(v);
          (blocks.get(key) || blocks.set(key, { v, rows: [] }).get(key)).rows.push(r);
        }
        let order = [...blocks.values()];
        if (dir[gcols[depth]]) {
          const num = numCol(col), d = dir[gcols[depth]] === "desc" ? -1 : 1;
          order.sort((a, b) => {
            const an = a.v == null, bn = b.v == null;
            if (an || bn) return an === bn ? 0 : an ? 1 : -1;
            return d * cmpVals(a.v, b.v, num);
          });
        }
        return order.flatMap(b => partition(b.rows, depth + 1));
      };
      return partition(all(), 0);
    }

    // Separator groups keep their place: rows filter/sort within a group; survivors
    // concatenate in group order, then ungrouped rows (manual groups needn't cover
    // all). An empty group contributes nothing; its header re-emits only if a row
    // remains.
    const cmp = makeCmp(state.sort || []), groups = spec._groups;
    if (!groups) return reduce(all(), cmp);
    const grouped = new Set(), out = [];
    for (const g of groups) { g.rows.forEach(r => grouped.add(r)); out.push(...reduce(g.rows, cmp)); }
    const rest = [];
    for (let r = 1; r <= nRow; r++) if (!grouped.has(r)) rest.push(r);
    return [...out, ...reduce(rest, cmp)];
  }

  // Rows of `view` on the current page. Clamps `state.page` in place (row count
  // shrinks as filters are typed; pager reads it back). `pageSize` 0 = one page.
  function pageSlice(view, state) {
    const n = state.pageSize;
    if (!n) { state.page = 0; return view; }
    const last = Math.max(0, Math.ceil(view.length / n) - 1);
    state.page = Math.min(Math.max(state.page || 0, 0), last);
    return view.slice(state.page * n, (state.page + 1) * n);
  }

  // Displayed text per column in original row order; view-independent, so
  // captured once from the initial render. `order[i]` = original 1-based index of
  // the i-th rendered body row (groups out of file order); absent = index order.
  // Skips group-header rows. `dataCells` drops rowspan group cells so indexes
  // line up with `cols`.
  function captureDisplay(el, cols, order) {
    const disp = {};
    cols.forEach(c => disp[c] = []);
    let i = 0;
    $$(el, "tbody tr").forEach(tr => {
      if (tr.classList.contains("lt-row-group")) return;
      const r = order ? order[i] : i + 1, cells = dataCells(tr);
      cols.forEach((c, ci) => disp[c][r - 1] = cells[ci]?.textContent ?? "");
      i++;
    });
    return disp;
  }

  function enhance(el, spec) {
    const opts = spec.interactive, cols = spec._cols || [],
          data = spec.data || {}, nRow = (data[cols[0]] || []).length,
          groups = spec._groups,
          // row -> group (to re-emit headers), and body render order (groups,
          // then ungrouped rows) so out-of-order manual groups map display text
          groupOf = {}, order = groups ? [] : null;
    if (groups) {
      const seen = new Set();
      groups.forEach(g => g.rows.forEach(r => { groupOf[r] = g; order.push(r); seen.add(r); }));
      for (let r = 1; r <= nRow; r++) if (!seen.has(r)) order.push(r);
    }
    // Page rows -> core's row list: insert a group header object (full-width
    // label row) when the group changes, so a group split across pages re-shows
    // its header; ungrouped rows get none.
    const withGroups = rows => {
      if (!groups) return rows;
      const out = []; let prev;
      for (const r of rows) {
        const g = groupOf[r];
        if (g !== prev) { if (g) out.push({ label: g.label, raw: g.raw }); prev = g; }
        out.push(r);
      }
      return out;
    };
    // Rowspan group columns lead the header (hidden from `cols`); the full
    // header order drives sort, so clicking one reorders its blocks (see
    // `_rowspan` in computeView)
    const nGroup = spec._rowspan ? spec._rowspan.length : 0,
          allCols = nGroup ? [...spec._rowspan, ...cols] : cols,
          // full column count: full-width rows must span group columns too
          nAll = nGroup + cols.length;
    // spec._display has text for *every* row (beyond the first-page cap); use it
    // for substring matching. Scraping the DOM (fallback) misses off-page rows.
    const disp = spec._display || captureDisplay(el, cols, order),
          // bottom header row: cells line up with `cols`
          hrow = [...$$(el, "thead tr")].pop(),
          // array `sort` = initial sort (see parseKey); `true` just enables it
          state = {
            filters: {}, predicates: {}, paints: [], page: 0, pageSize: 0,
            sort: Array.isArray(opts.sort) ? opts.sort.map(parseKey) : []
          };
    let view,          // filtered + sorted indices, cached across page turns
        sync = () => {};  // pager readout, replaced by addPaginate()
    // Hooks run on each new <tbody> to restore state a swap drops: expand carets
    // / details (addDetail), hidden columns (addColumnToggle). Args: <tbody>,
    // row indices.
    const postSwap = [];

    // `stale`: view changed (term/sort), not just page; recompute, go to page 1.
    const refresh = (stale = true) => {
      if (stale) {
        view = state.view = computeView(spec, disp, state); state.page = 0;
        state.paints.forEach(f => f(view));
      }
      const rows = pageSlice(view, state),
            // _viewRows = page rows with group headers; postSwap gets the same
            // list, one entry per <tbody> row
            vr = withGroups(rows),
            tmp = elem(el.ownerDocument, "template", {
              innerHTML: LT.buildHtml({ ...spec, _viewRows: vr })
            });
      const body = $(tmp.content, "tbody");
      if (!rows.length)  // no match: neutral symbol across all columns
        body.innerHTML = `<tr class="lti-empty"><td colspan="${nAll}">—</td></tr>`;
      else postSwap.forEach(f => f(body, vr));
      $(el, "tbody").replaceWith(body);
      sync(view.length);
    };

    // refresh() rebuilds the body synchronously (freezes large tables). uiRefresh()
    // shows a busy state (see busyRender). Paging stays direct (cheap); view
    // recomputes and detail toggles go through the busy wrapper.
    const wrap = el.closest(".lt-wrap");
    const uiRefresh = busyRender(wrap, (stale = true) => refresh(stale));
    // During construction each seeded filter/sort (forestly seeds a select and a
    // slider) would trigger a wasted full-table render, early ones before the pager
    // sets a page size (rendering *every* row). Suppress and coalesce into the one
    // final render below (`building` cleared just before it).
    let building = true, dirty = false;
    const requestRefresh = (stale = true) => {
      if (building) { dirty = true; return; }
      uiRefresh(stale);
    };

    // Controller for outside widgets (e.g. forestly's): `filter(id, fn)` registers
    // a predicate on a row's raw values (`{col: value}`, incl. hidden columns),
    // replacing it, or removing with null `fn`, then re-renders. `spec`/`state`
    // are read-only exposure. `bar` and `resetDetail` are added below.
    el._lt = {
      spec, state,
      // Re-render body. `stale` (default) recomputes view, page 1; `false` keeps
      // view and page (e.g. plot refit)
      refresh: (stale = true) => uiRefresh(stale),
      // Current filtered + sorted 1-based indices (all pages), e.g. for download,
      // which must honor typed filters (in state.filters, not predicates)
      view: () => view || computeView(spec, disp, state),
      filter(id, fn) {
        fn ? (state.predicates[id] = fn) : (delete state.predicates[id]);
        uiRefresh();
      }
    };

    // `filter` is normalized (R side) to { default?, cols? }: `default` covers
    // unnamed visible columns; `cols` maps column -> spec (`true` = plain box, `false` =
    // none, else typed). A typed filter on a hidden column has no header, so it becomes a
    // head-bar chip; the rest go under their headers.
    const flt = opts.filter,
          barCols = flt?.cols ?
            Object.keys(flt.cols).filter(c => flt.cols[c]?.type && flt.cols[c].type !== "auto" && !cols.includes(c)) : [];
    // Table-wide controls share one head row: search (absorbs free space), chips,
    // then icons (column menu, download)
    const headBar = (opts.search !== false || opts.hide || barCols.length || opts.download) ?
      elem(el.ownerDocument, "div", { className: "lti-bar" },
        fullRow(el.tHead || el.createTHead(), "lti-head", nAll, 0)) : null;
    // Data-column header labels, read before sort/resize decorate cells, so the
    // column menu shows displayed labels, not raw names
    const labels = dataCells(hrow).map(th => labelNodes(th).map(n => n.textContent).join("")),
          // plain-language queries name a column by its label (may hold spaces) or
          // its name
          labelOf = c => labels[cols.indexOf(c)] || c,
          names = Object.fromEntries(cols.flatMap(c => c == null ? [] : [[c, c], [labelOf(c), c]]));
    // Sort before filters join the header cells; `allCols` binds group headers
    // too
    if (opts.sort !== false) addSort(hrow, allCols, state, requestRefresh);
    if (opts.profile === "header") addProfile(hrow, cols, textual(spec), state);
    // Header filters: needed if a default applies or a named column is visible
    if (flt && (flt.default || (flt.cols && Object.keys(flt.cols).some(c => flt.cols[c] && cols.includes(c)))))
      addFilter(hrow, cols, flt, textual(spec), state, requestRefresh, opts.profile === "filter");
    const layout = opts.resize ? fixedLayout(el, hrow, cols.length, nGroup) : null;
    if (opts.resize) addResize(el, layout);
    // DOM order = visual order. Chips group is always created with a bar so callers
    // can add chips via el._lt.chips (empty collapses, CSS :empty); the column menu
    // stays in the icons group, even as a labeled chip, so filter chips stay together.
    if (opts.search !== false) addSearch(headBar, el, state, requestRefresh, names, labelOf, () => queryExamples(textual(spec), cols, labelOf));
    const chips = headBar ?
      elem(el.ownerDocument, "div", { className: "lti-chips" }, headBar) : null;
    if (barCols.length) addControlFilters(chips, barCols, flt.cols, textual(spec), state, requestRefresh, opts.profile === "filter");
    const icons = (opts.hide || opts.download) ?
      elem(el.ownerDocument, "div", { className: "lti-icons" }, headBar) : null;
    if (opts.hide)
      addColumnToggle(icons, el, hrow, cols, labels, opts.hide, layout, postSwap);
    if (opts.download) addDownload(icons, el, spec, cols, labels, opts.download);
    // Control bar (`.lti-bar`; null if no table-wide controls) for callers to add
    // widgets to; `chips` is its chip group (null only without a bar), home for
    // caller chips
    el._lt.bar = headBar;
    el._lt.chips = chips;
    // Row detail re-renders via the same seam; toggling changes no view, so a
    // plain re-render suffices
    if (opts.detail) {
      const detail = addDetail(el, spec, nAll, state, opts.detail, () => refresh(false));
      postSwap.push(detail);
      // Bust detail cache and re-render open details (one row or all), for
      // widgets that change the detail callback's output
      el._lt.resetDetail = detail.reset;
    }
    // controls built; allow the coalesced final render
    building = false;
    // `pager` = page sizes to offer; first is initial
    if (opts.pager) {
      const sizes = Array.isArray(opts.pager) ? opts.pager : [10, 25, 50, 100];
      sync = addPaginate(el, nAll, sizes, nRow, state, () => refresh(false));
      refresh();  // cut the full render down to the first page
    } else if (state.sort.length || opts.detail || dirty) {
      // core rendered file order; re-render for initial sort, seeded filter
      // (`dirty`), and/or expand carets
      refresh();
    }
  }

  // `type="search"` gives the browser's affordance and clear button, so no icon
  // or translatable placeholder; label is for screen readers.
  function searchInput(doc, label) {
    return elem(doc, "input", {
      type: "search", className: "lti-search", "aria-label": label
    });
  }

  // Full-width table row for a table-wide control. Inside the table keeps it as
  // wide as the table and inside the `.lt-wrap` scroll box. Returns its cell.
  function fullRow(sect, cls, nCol, pos) {
    const row = sect.insertRow(pos);
    row.className = cls;
    return elem(sect.ownerDocument, "td", { colSpan: nCol }, row);
  }

  // Run `fn` (reads its own live state) after `ms` of quiet; `.now()` flushes at
  // once (Enter, drag end). Used by search/filter boxes and slider.
  function debounce(fn, ms = 400) {
    let timer;
    const run = () => { clearTimeout(timer); timer = setTimeout(fn, ms); };
    run.now = () => { clearTimeout(timer); fn(); };
    return run;
  }

  // Show a busy state (.lti-busy on `wrap`) for slow synchronous renders. Class
  // paints only if set *before* the blocking pass, so predict from the previous
  // cost: run inline unless last run exceeded BUSY_MS. `run(arg)` does the work;
  // the returned function forwards its arg. Used by view recomputes and detail
  // toggles.
  function busyRender(wrap, run) {
    const BUSY_MS = 120;
    let frame, lastCost = 0;
    const timed = arg => {
      const t = performance.now();
      run(arg);
      lastCost = performance.now() - t;
    };
    return arg => {
      if (!wrap || lastCost < BUSY_MS) return timed(arg);
      wrap.classList.add("lti-busy");
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => requestAnimationFrame(() => {
        try { timed(arg); } finally { wrap.classList.remove("lti-busy"); }
      }));
    };
  }

  // Debounce typing; Enter or blur applies at once. Longer than default: filter
  // recompute is far heavier than a slider nudge.
  function onType(input, apply) {
    const go = debounce(() => apply(input.value), 1000);
    // picking a datalist example (not typing) applies at once
    input.oninput = e => e.inputType && e.inputType !== "insertReplacementText" ? go() : go.now();
    input.onchange = go.now;
  }

  // Random example queries, built from real columns and values so each one works
  // as written. `prefix` is the column name for the table-wide box, "" for a
  // column's own box.
  const qv = v => /[\s,;:"]/.test(v) ? `"${v}"` : String(v),
        rnd = a => a[Math.floor(Math.random() * a.length)],
        hasData = v => v?.some(x => x != null && x !== ""),
        sample = gen => {
          const out = new Set();
          for (let i = 0; i < 30 && out.size < 6; i++) out.add(gen(i));
          return [...out];
        },
        colExample = (v, prefix) => {
          if (numCol(v)) {
            const s = v.filter(x => x != null).sort((x, y) => x - y),
                  at = f => +s[Math.floor((s.length - 1) * f)].toPrecision(3);
            return rnd([`${prefix}over ${at(.5)}`, `${prefix}under ${at(.5)}`, `${prefix}at least ${at(.75)}`, `${prefix}between ${at(.25)} and ${at(.75)}`]);
          }
          const u = [...new Set(v.filter(Boolean))], a = qv(rnd(u)), b = qv(rnd(u));
          return rnd([`${prefix}is ${a}`, `${prefix}is not ${a}`, `${prefix}contains ${a}`, `${prefix}does not contain ${a}`, `${prefix}is ${a} or ${prefix}is ${b}`]);
        },
        // table-wide: alternate numeric, text, and both; the first two are one of each
        queryExamples = (vals, cols, labelOf) => {
          const filled = cols.filter(c => hasData(vals[c])),
                ncs = filled.filter(c => numCol(vals[c])), tcs = filled.filter(c => !numCol(vals[c])),
                one = cs => { const c = rnd(cs); return colExample(vals[c], `${qv(labelOf(c))} `); },
                gens = [ncs.length && (() => one(ncs)), tcs.length && (() => one(tcs)),
                        ncs.length && tcs.length && (() => `${one(ncs)}${rnd([", ", " and "])}${one(tcs)}`)].filter(Boolean);
          return gens.length ? sample(i => gens[i % gens.length]()) : [];
        },
        columnExamples = v => hasData(v) ? sample(() => colExample(v, "")) : [];

  // Show `gen()` examples as a <datalist> on `input`, redrawn on each focus. The
  // list goes after `after` (the box's note) so it stays out of a bar's children.
  // The id is made at run time, so it never lands in static output.
  let tipId = 0;
  function addTips(input, gen, after = input) {
    const doc = input.ownerDocument, list = elem(doc, "datalist", { id: `lti-tips-${++tipId}` });
    input.setAttribute("list", list.id);
    after.after(list);
    const refill = () => {
      const ex = gen();
      list.replaceChildren(...ex.map(value => elem(doc, "option", { value })));
      return ex;
    };
    // the placeholder shows one sample; the title says the list is not exhaustive
    const [first] = refill();
    if (first) Object.assign(input, { placeholder: `e.g. ${first}`, title: "Examples, not the only options; any query works" });
    input.addEventListener("focus", refill);
  }

  // Table-wide search box in the shared head cell. The text stays as typed; a
  // line under the bar shows how it was read; random example queries drop down
  // from the box.
  function addSearch(cell, el, state, refresh, names, labelOf, examples) {
    const doc = el.ownerDocument, input = cell.appendChild(searchInput(doc, "Search")),
          note = elem(doc, "div", { className: "lti-nl" });
    cell.after(note);
    addTips(input, examples, note);
    onType(input, v => {
      const t = Q.parse(v, names);
      state.where = t;
      note.textContent = Q.parsed(t) ? Q.text(t, labelOf) : "";
      refresh();
    });
  }

  // CSV-escape: quote (doubling quotes) only if comma, quote, or newline.
  function csvField(v) {
    const s = v == null ? "" : String(v);
    return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  }

  // Button downloading the current view (all pages, `el._lt.view()`) as CSV.
  // `opt` = file name or `{file?, mode?}`; `mode: "raw"` exports `spec.data`
  // instead of displayed text (`spec._display`). Skips group columns (null in
  // `cols`). Uses Blob + <a>, no library.
  function addDownload(cell, el, spec, cols, labels, opt) {
    const doc = el.ownerDocument,
          o = typeof opt === "object" ? opt : { file: opt },
          raw = o.mode === "raw",
          file = (typeof o.file === "string" && o.file ? o.file : "table")
            .replace(/(\.csv)?$/i, ".csv"),
          keep = cols.map((c, i) => i).filter(i => cols[i] != null),
          btn = elem(doc, "button", {
            type: "button", className: "lti-download", title: "Download CSV",
            "aria-label": "Download table as CSV"
          }, cell);
    btn.onclick = () => {
      const src = (raw ? textual(spec) : spec._display) || {},
            lines = [keep.map(i => csvField(labels[i] ?? cols[i])).join(",")];
      for (const r of el._lt.view())
        lines.push(keep.map(i => csvField((src[cols[i]] || [])[r - 1])).join(","));
      const url = URL.createObjectURL(
        new Blob([lines.join("\n")], { type: "text/csv" }));
      elem(doc, "a", { href: url, download: file }).click();
      URL.revokeObjectURL(url);
    };
  }

  // Cycle a column asc -> desc -> unsorted in `state.sort`. Plain click sorts by
  // it alone; shift-click adds a tie-breaker (or re-cycles it in place).
  function cycle(state, col, additive) {
    const order = (state.sort || []).slice(),
          i = order.findIndex(k => k.col === col),
          dir = i < 0 ? "asc" : order[i].dir === "asc" ? "desc" : null;
    if (!additive) { state.sort = dir ? [{ col, dir }] : []; return; }
    if (i < 0) order.push({ col, dir });        // "asc" here
    else if (dir) order[i] = { col, dir };
    else order.splice(i, 1);
    state.sort = order;
  }

  // Click-to-sort headers (shift-click for several). Indicators and aria-sort
  // live on <th>s, which survive the <tbody> swap, so repaint needs no re-render.
  // Ordinals (₁ ₂ …) mark key order when several sort.
  function addSort(hrow, cols, state, refresh) {
    const doc = hrow.ownerDocument, marks = {};
    const paint = () => {
      for (const c in marks) {
        marks[c].th.removeAttribute("aria-sort");
        marks[c].ind.textContent = "";
      }
      const order = state.sort || [];
      order.forEach(({ col, dir }, i) => {
        const m = marks[col];
        if (!m) return;
        m.th.setAttribute("aria-sort", dir === "desc" ? "descending" : "ascending");
        m.ind.textContent = (dir === "desc" ? "▼" : "▲") +
          (order.length > 1 ? sub(i + 1) : "");
      });
    };
    $$(hrow, "th").forEach((th, ci) => {
      const col = cols[ci];
      if (col == null) return;
      th.classList.add("lti-sortable");
      // label only, so the resize grip (outside it) doesn't sort
      const nodes = labelNodes(th), lab = elem(doc, "span", { className: "lti-label" }),
            ind = elem(doc, "span", { className: "lti-sort" });
      th.prepend(lab, ind);
      lab.append(...nodes);
      marks[col] = { th, ind };
      lab.onclick = ind.onclick = e => { cycle(state, col, e.shiftKey); paint(); refresh(); };
    });
    paint();  // reflect initial sort
  }

  // Per-column filters, in the header cells (on a line of their own, after the
  // label and type tag) so the <tbody> swap keeps them and typed input. `flt` =
  // normalized { default?, cols? }: named spec else default. `true` = plain box;
  // typed = funnel + popover (see typedFilter).
  function addFilter(hrow, cols, flt, data, state, refresh, prof) {
    const doc = hrow.ownerDocument, hCells = dataCells(hrow),
          def = flt.default, explicit = flt.cols || {};
    cols.forEach((c, ci) => {
      const cell = hCells[ci],
            spec = autoSpec(c in explicit ? explicit[c] : def, data[c]);
      if (!spec || !filterable(data, c)) return;   // no filter on this column
      elem(doc, "br", {}, cell);
      if (spec === true) {                         // a plain search box
        const input = cell.appendChild(searchInput(doc, `Filter ${c}`)),
              note = elem(doc, "div", { className: "lti-nl" });
        input.after(note);
        addTips(input, () => columnExamples(data[c]), note);
        onType(input, v => {
          const t = Q.parse(v, {}, c);
          t ? (state.filters[c] = t) : delete state.filters[c];
          note.textContent = Q.parsed(t) ? Q.text(t, () => null) : "";
          refresh();
        });
      } else                                       // a typed funnel under the label
        cell.append(typedFilter(doc, c, spec, data, state, refresh, null, prof));
    });
  }

  // Column profile: a mini bar chart with the summary stats as its tooltip. A
  // histogram of up to K equal-width bins for numbers/dates, one bar per category
  // (most frequent first) for text; empty svg (keeps the header aligned) for text
  // where over half the values are distinct (not categorical). Bars
  // count all rows lightly, and the rows in the current view darkly (`state.paints`
  // repaint it when the view changes).
  function profile(doc, col, state) {
    const K = 10, vals = col.filter(v => v != null), sig = (x, d) => +x.toPrecision(d),
          p = elem(doc, "span", { className: "lti-prof" });
    const num = v => col.date ? Date.parse(v.replace(" ", "T")) : v,
          nums = vals.map(num), isNum = nums.every(Number.isFinite), m = new Map();
    for (const v of vals) m.set(v, (m.get(v) || 0) + 1);
    const nNA = col.length - vals.length, tip = [];
    let n = K, bin = () => -1;  // n bars; bin: value -> bar index (-1 for none)
    const slots = list => { n = list.length; const s = new Map(list.map((e, i) => [e[0], i])); bin = v => s.get(v) ?? -1; };
    // no bars (empty svg as placeholder) for an all-NA or too-distinct text column
    if (!vals.length || (!isNum && m.size > vals.length / 2)) n = 0;
    else if (isNum) {
      const lo = nums.reduce((a, b) => Math.min(a, b)), hi = nums.reduce((a, b) => Math.max(a, b)),
            at = x => col.date ? vals[nums.indexOf(x)] : sig(x, 6);
      tip.push(`min ${at(lo)}`, `max ${at(hi)}`);
      col.date || tip.push(`mean ${sig(nums.reduce((a, b) => a + b) / nums.length, 4)}`);
      nNA && tip.push(`${Math.round(100 * nNA / col.length)}% NA`);
      n = Math.min(K, m.size);  // never more bins than distinct values
      bin = v => Math.min(n - 1, Math.floor((num(v) - lo) / (hi - lo || 1) * n));
    } else {
      const all = [...m].sort((a, b) => b[1] - a[1]), cut = m.size > 5;
      slots(all);
      // count distinct only when truncated; readers can count the listed values
      cut && tip.push(`${m.size + (nNA > 0)} distinct`);
      tip.push((cut ? "top " : "") + all.slice(0, 5).map(([v, k]) => `${v} (${k})`).join(", "));
      nNA && tip.push(`${nNA} NA`);
    }
    const bars = col.map(v => v == null ? -1 : bin(v)),
          count = rows => { const c = Array(n).fill(0); for (const r of rows) bars[r - 1] >= 0 && c[bars[r - 1]]++; return c; },
          full = count(col.map((_, i) => i + 1)), max = Math.max(...full),
          rects = (c, cls) => c.map((k, i) =>
            `<rect${cls} x="${i}" y="${1 - k / max}" width=".9" height="${k / max}"/>`).join(""),
          paint = rows => p.innerHTML = `<svg viewBox="0 0 ${n || 1} 1" preserveAspectRatio="none">${rects(full, "")}${rows.length < col.length ? rects(count(rows), ' class="s"') : ""}</svg>`;
    p.title = tip.filter(Boolean).join("; ");
    state.paints.push(paint);
    paint(state.view || col.map((_, i) => i + 1));
    return p;
  }

  // Profile in the header cell, after the type tag (`profile: "header"`)
  function addProfile(hrow, cols, data, state) {
    const hCells = dataCells(hrow);
    cols.forEach((c, ci) => {
      hCells[ci].append(elem(hrow.ownerDocument, "br"), profile(hrow.ownerDocument, data[c], state));
    });
  }

  // `"auto"` filter: pick the widget from the column's data. Numbers get a range
  // slider (text if constant), so do dates; strings with few distinct values a
  // checklist; anything else a text funnel (no widget, just the search box).
  const autoSpec = (spec, col = []) => {
    if (spec?.type !== "auto") return spec;
    const vals = col.filter(v => v != null), n = new Set(vals).size;
    const kind = vals.every(v => typeof v === "number") || col.date ? n > 1 && { type: "range" }
      : vals.every(v => typeof v === "string") && n <= 10 && { type: "checklist" };
    return kind || { type: "text" };
  };

  // Filterable only with a non-blank value; plot-only `into` columns have no data.
  const filterable = (data, col) => {
    const a = data && data[col];
    return Array.isArray(a) && a.some(v => v != null && v !== "");
  };

  // Expandable row detail. `detailOpt` = array of column names (one-row table of
  // their displayed values) or callback `(rawRow, index, displayedRow) => spec`
  // (or global name), called on first expand and cached. Returns
  // `decorate(body, rows)`, run per <tbody> render: prepends an expand caret per
  // row and inserts a full-width detail row (via LT.render, so it can itself be
  // interactive) after open rows. Expanded rows tracked by original index, so
  // detail follows its row. `detailOpt` resolves lazily, so late globals work.
  function addDetail(el, spec, nCol, state, detailOpt, rerender) {
    // `nCol` = full width, incl. group columns
    const doc = el.ownerDocument, cache = {};
    state.expanded = new Set();
    // Row as {col: value} (all columns, incl. hidden) from `src`: spec.data =
    // raw, spec._display = formatted
    const pick = (src, r) => {
      const o = {}; for (const c in src) o[c] = src[c]?.[r - 1] ?? null; return o;
    };
    const build = r => {
      if (r in cache) return cache[r];
      const disp = pick(spec._display || {}, r);
      let out = null;
      if (Array.isArray(detailOpt)) {
        // column names: one-row table of displayed values (may be hidden columns)
        const data = {};
        for (const c of detailOpt) data[c] = [disp[c] ?? null];
        out = { data };
      } else {
        // callback or its global name
        const fn = typeof detailOpt === "function" ? detailOpt : root[detailOpt];
        if (typeof fn === "function") out = fn(pick(spec.data || {}, r), r, disp);
      }
      return cache[r] = out;
    };
    // slow renders (big detail, reset rebuild) show busy state via `busy(fn)`
    const wrap = el.closest(".lt-wrap"), busy = busyRender(wrap, fn => fn());
    const setCaret = (btn, open) => {
      btn.textContent = open ? "▾" : "▸";
      btn.setAttribute("aria-expanded", String(open));
    };
    // Build detail once, hidden after its <tr>; caret toggles visibility. null if
    // callback yields none.
    const openDetail = (tr, r) => {
      const child = build(r);
      if (!child) return null;
      const row = elem(doc, "tr", { className: "lti-detail", hidden: true });
      tr.after(row);
      LT.render(elem(doc, "div", {}, elem(doc, "td", { colSpan: nCol }, row)), child);
      return row;
    };
    const ensureDetail = (tr, r) => {
      const d = tr.nextElementSibling;
      return d?.classList.contains("lti-detail") ? d : openDetail(tr, r);
    };
    // base width (no detail), captured per render by presize
    let baseW = 0;
    // Grow explicit `width` (not min-width, so container max-width still caps) to
    // fit a wider detail. Only grows: reopening never jumps.
    const grow = () => {
      const w = Math.ceil(el.getBoundingClientRect().width);
      if (w > baseW && w > (parseFloat(el.style.width) || 0)) el.style.width = w + "px";
    };
    // toggle: flip the built detail's visibility
    const toggle = (tr, btn, r) => {
      const open = state.expanded.has(r);
      open ? state.expanded.delete(r) : state.expanded.add(r);
      setCaret(btn, !open);
      const d = ensureDetail(tr, r);
      if (!d) return;
      d.hidden = open;
      if (!open) grow();  // may be wider than table
    };
    // Pre-size from the first detail so typical expands don't jump width: at idle,
    // open it to measure, re-hide, grow table. Others stay deferred (grow on first
    // open). Re-runs per <tbody> render.
    const win = doc.defaultView, idle = win.requestIdleCallback || win.setTimeout;
    const presize = (body) => idle(() => {
      if (!body.isConnected) return;                   // replaced by newer render
      el.style.width = "";
      baseW = el.getBoundingClientRect().width;
      const c = $(body, ".lti-expand[aria-expanded='false']");
      if (!c) return;
      c.click();                                       // build + show
      grow();
      c.click();                                       // hide (stays built)
    });
    const decorate = (body, rows) => {
      [...body.rows].forEach((tr, i) => {
        const r = rows[i];
        if (typeof r !== "number") return;  // group-header row
        // first data cell (past group cells): caret goes in row's own first column
        const td0 = dataCells(tr)[0], open = state.expanded.has(r);
        if (!td0) return;
        const btn = elem(doc, "button", {
          type: "button", className: "lti-expand", "aria-label": "Toggle detail"
        });
        setCaret(btn, open);
        btn.onclick = () => toggle(tr, btn, r);
        td0.prepend(btn);
        if (open) { const d = ensureDetail(tr, r); if (d) d.hidden = false; }
      });
      presize(body);
    };
    // Drop cached detail (one row or all) and re-render; callback re-runs and
    // detail (with its sort/filter state) rebuilds.
    decorate.reset = r => {
      if (r == null) for (const k in cache) delete cache[k];
      else delete cache[r];
      busy(rerender);
    };
    return decorate;
  }

  // Table <colgroup>, created if core emitted none (only with explicit R widths):
  // `nGroup` leading <col>s for rowspan group columns, then one per data column,
  // matching core's layout.
  function colGroup(el, nCol, nGroup = 0) {
    let g = $(el, "colgroup");
    if (!g) {
      const doc = el.ownerDocument;
      g = elem(doc, "colgroup");
      for (let i = 0; i < nGroup + nCol; i++) elem(doc, "col", {}, g);
      // after <caption>, before <thead>
      el.caption ? el.caption.after(g) : el.prepend(g);
    }
    return [...g.children];
  }

  // Fixed layout for column resize. Widths live on <colgroup> (outside <tbody>),
  // surviving re-renders. `freeze()` pins every column at its current width once,
  // so later changes move one column without reflow. `natural(i)` = column i's
  // content width (unconstrained reflow, widths restored). `setWidth(i, w, min)`
  // sets column i to `w` px (>= `min`), resizing the table by the difference.
  function fixedLayout(el, hrow, nCol, nGroup = 0) {
    const ths = [...$$(hrow, "th")],
          cs = colGroup(el, nCol, nGroup), wOf = e => e.getBoundingClientRect().width;
    const freeze = () => {
      if (el.classList.contains("lti-fixed")) return;
      const w = ths.map(wOf);
      el.style.width = wOf(el) + "px";
      cs.forEach((c, i) => c.style.width = w[i] + "px");
      el.classList.add("lti-fixed");
    };
    const natural = i => {
      const keep = cs.map(c => c.style.width), tw = el.style.width;
      cs.forEach(c => c.style.width = "");
      el.style.width = "";
      el.classList.remove("lti-fixed");
      const w = wOf(ths[i]);  // forces the reflow
      cs.forEach((c, j) => c.style.width = keep[j]);
      el.style.width = tw;
      el.classList.add("lti-fixed");
      return w;
    };
    const setWidth = (i, w, min = MIN_COL) => {
      const old = parseFloat(cs[i].style.width);
      cs[i].style.width = Math.max(w, min) + "px";
      el.style.width =
        `${parseFloat(el.style.width) + parseFloat(cs[i].style.width) - old}px`;
    };
    // `dataCs` drops group <col>s: index by data-column position
    return { ths, cs, dataCs: cs.slice(nGroup), freeze, natural, setWidth };
  }

  // Drag-to-resize: grip on each header's right edge. First drag switches to
  // fixed layout (see fixedLayout) so one edge moves alone. Double-click fits
  // content.
  function addResize(el, layout) {
    const doc = el.ownerDocument, { ths, cs, freeze, natural, setWidth } = layout;
    ths.forEach((th, i) => {
      const grip = elem(doc, "div", { className: "lti-resizer" }, th);
      grip.ondblclick = e => {
        e.stopPropagation();
        freeze();
        setWidth(i, natural(i));
      };
      grip.onpointerdown = e => {
        e.stopPropagation();
        freeze();
        const x0 = e.clientX, w0 = parseFloat(cs[i].style.width);
        el.classList.add("lti-resizing");
        // default min width; CSS clips overflow when shrunk
        drag(e, ev => setWidth(i, w0 + ev.clientX - x0),
          () => el.classList.remove("lti-resizing"));
      };
    });
  }

  // Column-visibility menu: eye button (or a chip, if `opt.label`) opening a
  // checklist, one box per column.
  // Unchecking sets `hidden` on the header and body cells (a <tbody> swap drops
  // it, so postSwap re-applies). `opt` = `true` (all shown) or `{ hidden: [...] }`
  // (start hidden). `layout` (resize) also hides the <col> so a fixed table reflows.
  function addColumnToggle(cell, el, hrow, cols, labels, opt, layout, postSwap) {
    const doc = el.ownerDocument,
          start = (opt && opt.hidden) || [], hidden = new Set();
    // Show/hide column i's cell in a row (data-cell index), skipping the colspan
    // cell of detail/empty rows (no column's own)
    const setCell = (tr, i, on) => {
      const c = dataCells(tr)[i];
      if (c && c.colSpan === 1) c.hidden = on;
    };
    // re-hide on each new <tbody>
    postSwap.push(body => hidden.forEach(i => {
      for (const tr of body.rows) setCell(tr, i, true);
    }));
    // Spanner row merges cells, so column i isn't cell i there; handled by
    // applySpan. Map each spanner cell to its column range (skipping row-group
    // placeholders): hide a colspan-1 slot outright; shrink a real spanner's
    // colSpan, hiding it only when all its columns are gone.
    const nGrp = [...hrow.children].length - dataCells(hrow).length,
          spanRow = [...el.rows].find(tr => tr.classList.contains("lt-spanner-row")),
          spanCells = spanRow ? dataCells(spanRow).slice(nGrp) : [];
    let col0 = 0;
    spanCells.forEach(c => { c._span = c.colSpan; c._start = col0; col0 += c._span; });
    // Recompute spanner cells from `hidden` (idempotent): colSpan = columns still
    // showing; hidden when none.
    const applySpan = () => {
      for (const c of spanCells) {
        let gone = 0;
        for (let j = c._start; j < c._start + c._span; j++) if (hidden.has(j)) gone++;
        c.colSpan = Math.max(1, c._span - gone);
        c.hidden = gone >= c._span;
      }
    };
    // Show/hide column i everywhere: <col> (fixed layout only) and per-column
    // cells (headers, filters, body, plot axis footer), plus spanners via
    // applySpan. setCell's colspan guard skips other full-width rows. <thead>/
    // <tfoot> survive a <tbody> swap; only a fresh <tbody> needs postSwap.
    const apply = i => {
      const on = hidden.has(i);
      if (layout?.dataCs[i]) layout.dataCs[i].hidden = on;
      for (const tr of el.rows)
        if (!tr.classList.contains("lt-spanner-row")) setCell(tr, i, on);
      applySpan();
    };
    const wrap = elem(doc, "span", { className: "lti-cols" }, cell),
          btn = opt?.label ?
            Object.assign(makeChip(doc, opt.label).el, { role: "button", tabIndex: 0 }) :
            elem(doc, "button", {
              type: "button", title: "Show/Hide columns",
              "aria-label": "Show/Hide columns"
            });
    btn.setAttribute("aria-expanded", "false");
    wrap.append(btn);
    const menu = elem(doc, "div", { className: "lti-menu", hidden: true }, wrap);
    // checkbox per column; `sub` indents under a spanner header
    const addBox = (i, sub) => {
      const c = cols[i];
      if (c == null) return;
      const label = elem(doc, "label", sub ? { className: "lti-sub" } : {}, menu),
            box = elem(doc, "input", { type: "checkbox", checked: true }, label);
      label.append(labels[i] ?? c);
      if (start.includes(c)) { box.checked = false; hidden.add(i); }
      box.onchange = () => {
        box.checked ? hidden.delete(i) : hidden.add(i);
        apply(i);
      };
    };
    // Group boxes under spanners: labels can repeat across spanners (auto-span's
    // "Sepal.Length"/"Petal.Length" both show "Length"), so flat is ambiguous.
    // Walk the spanner row: group header before a real spanner's columns; unspanned
    // columns alone. No spanner row: flat.
    if (spanCells.length) for (const c of spanCells) {
      const span = c.classList.contains("lt-spanner");
      if (span) elem(doc, "div", { className: "lti-group", textContent: c.textContent }, menu);
      for (let i = c._start; i < c._start + c._span; i++) addBox(i, span);
    } else cols.forEach((_, i) => addBox(i));
    cols.forEach((_, i) => apply(i));  // apply initially hidden columns
    const open = on => {
      menu.hidden = !on;
      btn.setAttribute("aria-expanded", String(on));
    };
    btn.onclick = e => { e.stopPropagation(); open(menu.hidden); };
    btn.onkeydown = e => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); btn.click(); } };
    on(doc, "click", e => { if (!wrap.contains(e.target)) open(false); });
    on(doc, "keydown", e => { if (e.key === "Escape") open(false); });
  }

  // --- Typed column filters (`filter` named-list form). A typed spec is
  // {type:"select"|"range"|"checklist", label?, choices?, min?, max?, step?,
  // value?, selected?}, rendered as a funnel + popover under its header (visible
  // column) or a labeled head-bar chip (hidden; its data is still in spec.data,
  // which computeView filters). The popover holds an expression box AND a widget
  // (dropdown, slider, or checklist) editing the same term (state.filters[col]),
  // kept in sync: the widget is a friendly face on a typeable expression.

  // Filter term <-> widget value, per type. `null` parse = a hand-typed term the
  // widget can't show: widget goes neutral, box stays authoritative.
  // value of the missing-value ("NA") choice; not a string any data holds
  const NA = "\0NA",
        selExpr = v => v === "" ? "" : v === NA ? "x == null" : `x == ${JSON.stringify(String(v))}`,
        selParse = s => {
          const m = /^\s*x\s*==\s*(?:(['"])([\s\S]*)\1|null)\s*$/.exec(s || "");
          return m ? (m[1] ? m[2] : NA) : null;
        },
        // range over numbers (`x >= 1 && x <= 3`) or, with `labels` (dates), over
        // their indices written as quoted labels (`x >= "2024-01-05"`)
        rngExpr = (lo, hi, min, max, labels) => lo <= min && hi >= max ? "" :
          labels ? `x >= ${JSON.stringify(labels[lo])} && x <= ${JSON.stringify(labels[hi])}`
            : `x >= ${lo} && x <= ${hi}`,
        rngParse = (s, labels) => {
          const m = /^\s*x\s*>=\s*("[^"]*"|-?[\d.]+)\s*&&\s*x\s*<=\s*("[^"]*"|-?[\d.]+)\s*$/.exec(s || "");
          if (!m) return null;
          // a quoted bound is a date label (unknown label or no labels: can't show)
          const at = t => t[0] !== '"' ? parseFloat(t) : labels ? labels.indexOf(JSON.parse(t)) : NaN,
                p = [at(m[1]), at(m[2])];
          return p.some(v => !isFinite(v) || (labels && v < 0)) ? null : p;
        },
        rngShow = (p, cfg) => cfg.labels ? `${cfg.labels[p[0]]} – ${cfg.labels[p[1]]}` : `${p[0]} – ${p[1]}`,
        // keeps rows whose value is checked; all checked -> "" (no filter), none ->
        // "[].includes(x)" (no rows). NA is `null` in the list, matched via `x ?? null`.
        setExpr = (sel, all) => {
          if (sel.length === all.length) return "";
          const vals = sel.map(v => v === NA ? null : String(v));
          return `${JSON.stringify(vals)}.includes(x${vals.includes(null) ? " ?? null" : ""})`;
        },
        setParse = s => {
          const m = /^\s*(\[[\s\S]*\])\.includes\(\s*x\s*(?:\?\?\s*null\s*)?\)\s*$/.exec(s || "");
          if (!m) return null;
          try { return JSON.parse(m[1]).map(v => v === null ? NA : v); } catch (e) { return null; }
        };

  // "Nice" slider step: 1/2/5 x 10^k nearest ~1% of span (~50-100 increments),
  // like pretty(). Integer columns round to a whole step. Degenerate span: 0.1 / 1.
  function niceStep(span, integer) {
    if (!(span > 0) || !isFinite(span)) return integer ? 1 : 0.1;
    const raw = span / 100, mag = Math.pow(10, Math.floor(Math.log10(raw)));
    const step = [1, 2, 5, 10].find(m => m * mag >= raw) * mag;
    return integer ? Math.max(1, Math.round(step)) : step;
  }

  // Fill a typed spec's choices (select) or min/max/step (range) from column data
  // when R omitted them, so `list(x = "select")` / `"range"` needs no bounds.
  // Returns a copy.
  function resolveSpec(spec, column) {
    if (spec.type === "select" || spec.type === "checklist") {
      let choices = spec.choices;
      if (!choices) {
        const seen = new Set(), vals = [];
        for (const v of column) if (v != null && !seen.has(v)) { seen.add(v); vals.push(v); }
        vals.sort((a, b) => typeof a === "number" && typeof b === "number"
          ? a - b : String(a).localeCompare(String(b)));
        choices = vals.map(v => ({ value: String(v), label: String(v) }));
      }
      // missing values get their own choice, so they can be selected too
      if (column.some(v => v == null)) choices = [...choices, { value: NA, label: "NA" }];
      // select gets a leading blank "no filter" choice; checklist starts all
      // checked (also "no filter"), so needs none
      if (spec.type === "select" && !choices.some(o => o.value === ""))
        choices = [{ value: "", label: "" }, ...choices];
      return { ...spec, choices };
    }
    // dates: the slider steps through the distinct values present (by index)
    if (spec.type === "range" && column.date) {
      const labels = [...new Set(column.filter(v => v != null))].sort();
      return { ...spec, labels, min: 0, max: labels.length - 1, step: 1 };
    }
    let { min, max, step } = spec;
    let lo = Infinity, hi = -Infinity, allInt = true;
    if (min == null || max == null || step == null) {
      for (const v of column) {
        const n = Number(v);
        if (isFinite(n)) {
          if (n < lo) lo = n;
          if (n > hi) hi = n;
          if (!Number.isInteger(n)) allInt = false;
        }
      }
      if (!isFinite(lo)) { lo = 0; hi = 1; }
    }
    const loB = min != null ? min : lo, hiB = max != null ? max : hi;
    if (step == null) step = niceStep(hiB - loB, allInt);
    // tidy() clears float dust; derived endpoints snap outward to whole steps so
    // they bracket the data (extreme rows aren't dropped)
    const tidy = x => Math.round(x * 1e9) / 1e9;
    if (min == null) min = tidy(Math.floor(lo / step) * step);
    if (max == null) max = tidy(Math.ceil(hi / step) * step);
    return { ...spec, min, max, step };
  }

  // Dropdown of {value, label}; `onInput(value)` on change.
  function makeSelect(doc, options, onInput) {
    const sel = elem(doc, "select", { className: "lti-filter-pick" });
    options.forEach(o => elem(doc, "option", { value: o.value, textContent: o.label }, sel));
    sel.onchange = () => onInput(sel.value);
    return { el: sel, set: v => sel.value = v };
  }

  // {value, label} checkboxes (all start checked); `onInput` gets the checked
  // values on change. Returns { el: [<label>...], set(values) }. On LT.ui so
  // callers can reuse it in their own popover (e.g. forestly's treatment-group
  // picker).
  function makeChecklist(doc, options, onInput) {
    const boxes = options.map(o => {
      const label = elem(doc, "label", { className: "lti-check" }),
            box = elem(doc, "input", { type: "checkbox", checked: true, value: o.value }, label);
      label.append(o.label);
      return { o, box, label };
    });
    const emit = () => onInput(boxes.filter(b => b.box.checked).map(b => b.o.value));
    boxes.forEach(b => b.box.onchange = emit);
    return {
      el: boxes.map(b => b.label),
      set: vals => boxes.forEach(b => b.box.checked = vals.includes(b.o.value))
    };
  }

  // Control-bar chip: label, caller's control (funnel popover), summary slot.
  // `mark(on)` toggles active highlight (color only); `summarize(text)` sets the
  // readout. Returns { el, mark, summarize }. Used by typed-filter chips; on
  // LT.ui so callers (e.g. forestly) share it.
  function makeChip(doc, label, control) {
    const el = elem(doc, "span", { className: "lti-chip" });
    elem(doc, "span", { className: "lti-chip-name", textContent: label }, el);
    const cur = elem(doc, "span", { className: "lti-chip-cur" }, el);
    if (control) el.append(control);
    return {
      el,
      mark: on => el.classList.toggle("lti-on", !!on),
      summarize: text => (cur.textContent = text)
    };
  }

  // Two-thumb range slider: track, fill, two <button> thumbs. Avoids native
  // <input type=range> (vendor CSS, stacked-input z-index hacks). Thumbs drag via
  // drag(), arrow keys step, Home/End jump; low never passes high. `cfg` =
  // {min, max, step}; `onInput([lo, hi])` fires on commit. Returns { el, set([lo, hi]) }.
  function makeSlider(doc, cfg, onInput, onMove) {
    const min = cfg.min, max = cfg.max, span = max - min || 1,
          step = cfg.step || span / 100,
          track = elem(doc, "div", { className: "lti-slider" }),
          fill = elem(doc, "div", { className: "lti-slider-fill" }, track),
          mk = lab => elem(doc, "button", {
            type: "button", className: "lti-thumb", role: "slider",
            "aria-label": lab, "aria-valuemin": min, "aria-valuemax": max
          }, track),
          thumbs = [mk("Minimum"), mk("Maximum")];
    let val = [min, max];
    // paint() tracks live; onInput never fires mid-drag (a live filter reflows
    // the table and shifts the chip under the cursor), so drag commits on release
    // (fire.now via onEnd). Arrow keys repaint live but only debounce the filter,
    // batching rapid steps/autorepeat.
    const fire = debounce(() => onInput(val.slice())),
          // fire only if `val` moved (not a bare click or arrow at an end)
          changed = from => val[0] !== from[0] || val[1] !== from[1];
    const pct = v => (v - min) / span * 100,
          snap = v => {
            const s = Math.round((v - min) / step) * step + min;
            return Math.min(max, Math.max(min, Math.round(s * 1e6) / 1e6));
          },
          paint = () => {
            thumbs.forEach((t, i) => {
              t.style.left = pct(val[i]) + "%";
              t.setAttribute("aria-valuenow", val[i]);
            });
            fill.style.left = pct(val[0]) + "%";
            fill.style.right = `${100 - pct(val[1])}%`;
          },
          move = (i, v) => {       // update + repaint, no filtering
            val[i] = snap(v);
            if (val[0] > val[1]) val = [Math.min(...val), Math.max(...val)];
            paint();
            onMove && onMove(val.slice());  // live readout
          };
    thumbs.forEach((t, i) => {
      const at = clientX => {
        const r = track.getBoundingClientRect();
        return min + span * Math.min(1, Math.max(0, (clientX - r.left) / r.width));
      };
      // filter on release only, and only if the range moved
      t.onpointerdown = e => {
        t.focus();
        const from = val.slice();
        drag(e, ev => move(i, at(ev.clientX)), () => changed(from) && fire.now());
      };
      t.onkeydown = e => {
        const d = { ArrowLeft: -1, ArrowDown: -1, ArrowRight: 1, ArrowUp: 1 }[e.key];
        const from = val.slice();
        if (d) move(i, val[i] + d * step);
        else if (e.key === "Home") move(i, min);
        else if (e.key === "End") move(i, max);
        else return;
        changed(from) && fire();
        e.preventDefault();
      };
    });
    paint();
    return { el: track, set: v => { val = v.slice(); paint(); } };
  }

  // Funnel button toggling a floating panel from `build(panel)`; closes on outside
  // click or Escape. Returns the wrapper. `host` (e.g. a chip) replaces the funnel
  // as click target, so the whole chip toggles and the panel aligns with it.
  function popover(doc, label, build, onClose, host) {
    const wrap = elem(doc, "span", { className: "lti-pop" }),
          btn = elem(doc, "button", {
            type: "button", className: "lti-funnel", title: label,
            "aria-label": label, "aria-expanded": "false"
          }, wrap),
          panel = elem(doc, "div", { className: "lti-pop-panel", hidden: true }, wrap);
    build(panel);
    // Keep the panel inside the scroll box: default left-aligned, but near the
    // right edge it would add a horizontal scrollbar, so right-align. Limit is the
    // box's right edge, not the viewport's.
    const place = () => {
      panel.style.left = panel.style.right = "";  // CSS default (left:0)
      const vw = (doc.defaultView || window).innerWidth,
            box = wrap.closest(".lt-wrap"),
            limit = Math.min(vw, box ? box.getBoundingClientRect().right : vw);
      if (panel.getBoundingClientRect().right > limit - 4) {
        panel.style.left = "auto"; panel.style.right = "0";
      }
    };
    const open = on => {
      const was = !panel.hidden;
      panel.hidden = !on;
      btn.setAttribute("aria-expanded", String(on));
      if (on) place(); else if (was) onClose && onClose();
    };
    // click target: whole chip if hosted (panel flush via CSS), else funnel wrap;
    // clicks inside the panel mustn't close it
    const anchor = host || wrap;
    anchor.onclick = e => { if (!panel.contains(e.target)) open(panel.hidden); };
    // Close on outside press, not click: a widget re-renders the table, so press
    // and release can land on different elements and fire a stray outside click
    // (native <select> pick). The press is always inside, so guard pointerdown.
    on(doc, "pointerdown", e => { if (!anchor.contains(e.target)) open(false); });
    on(doc, "keydown", e => { if (e.key === "Escape") open(false); });
    return wrap;
  }

  // One bundle per filter type: a new type is one entry. `describe(term, cfg)` =
  // chip summary; `init(cfg)` = term for the default; `parse(term)` = widget value,
  // or null for a hand-typed term (widget hides); `build(doc, cfg, setTerm)` =
  // syncing editor `{ el, reflect(term) }`, where `el` (node or array) goes in the
  // popover and the widget writes the term via `setTerm`. Backed by the term <->
  // value helpers above.
  const KINDS = {
    select: {
      describe: (t, cfg) => {
        const v = selParse(t);
        if (v == null) return t ? "⋯" : "";
        const o = cfg.choices.find(o => o.value === v);
        return o ? o.label : v;
      },
      init: cfg => selExpr(cfg.selected ?? ""),
      parse: selParse,
      build: (doc, cfg, setTerm) => {
        const w = makeSelect(doc, cfg.choices, v => setTerm(selExpr(v), ed)),
              ed = { el: w.el, reflect: t => { const v = selParse(t); w.set(v == null ? "" : v); } };
        return ed;
      }
    },
    range: {
      describe: (t, cfg) => { const p = rngParse(t, cfg.labels); return p ? rngShow(p, cfg) : t ? "⋯" : ""; },
      init: cfg => cfg.value ? rngExpr(cfg.value[0], cfg.value[1], cfg.min, cfg.max, cfg.labels) : "",
      parse: (t, cfg) => rngParse(t, cfg.labels),
      build: (doc, cfg, setTerm) => {
        const out = elem(doc, "span", { className: "lti-slider-out" }),
              show = p => out.textContent = rngShow(p, cfg),
              put = v => setTerm(rngExpr(v[0], v[1], cfg.min, cfg.max, cfg.labels), ed),
              w = makeSlider(doc, cfg, v => { show(v); put(v); }, show),
              ed = { el: [w.el, out], reflect: t => { const p = rngParse(t, cfg.labels) || [cfg.min, cfg.max]; w.set(p); show(p); } };
        return ed;
      }
    },
    // no widget: the funnel's popover holds only the expression box (the term is
    // the search text itself)
    text: {
      describe: t => t,
      init: () => "",
      parse: t => t,
      build: () => ({ el: [], reflect: () => {} })
    },
    checklist: {
      // chip summary: chosen labels (few) else a count; empty if all checked
      describe: (t, cfg) => {
        const sel = setParse(t);
        if (sel == null) return t ? "⋯" : "";
        const labs = cfg.choices.filter(o => sel.includes(o.value)).map(o => o.label);
        return labs.length <= 2 ? labs.join(", ") : `${labs.length} selected`;
      },
      // `[].concat`: a scalar `selected` from R still seeds
      init: cfg => setExpr([].concat(cfg.selected ?? cfg.choices.map(o => o.value)), cfg.choices),
      parse: setParse,
      build: (doc, cfg, setTerm) => {
        const all = cfg.choices.map(o => o.value),
              w = makeChecklist(doc, cfg.choices, sel => setTerm(setExpr(sel, cfg.choices), ed)),
              ed = { el: w.el, reflect: t => { const sel = setParse(t); w.set(sel == null ? all : sel); } };
        return ed;
      }
    }
  };

  // Build a typed column filter element. Funnel + popover is shared: head-bar chip
  // (label + summary around the funnel) if `chipLabel` is a string, else a bare
  // funnel under the header (null).
  function typedFilter(doc, col, spec, data, state, refresh, chipLabel, prof) {
    const cfg = resolveSpec(spec, data[col] || []),
          kind = KINDS[cfg.type],
          editors = [];       // expression box + widget, kept in sync
    let mark = () => {},       // paints active state once `root` exists
        showSummary = () => {},  // chip value readout (chip only)
        widget = null;         // wrapper; hidden when it can't show the term
    // Set the term, re-render, reflect into every editor but `from`, so slider and
    // box update each other. Widget hides on a hand-typed term it can't show, so it
    // never contradicts the box.
    const setTerm = (expr, from) => {
      expr ? (state.filters[col] = expr) : delete state.filters[col];
      refresh();
      const cur = state.filters[col] || "";
      editors.forEach(e => e !== from && e.reflect(cur));
      if (widget) widget.hidden = !!cur && kind.parse(cur, cfg) == null;
      mark(cur);
    };
    // Hidden column: funnel in a labeled chip (makeChip), also the popover's click
    // target; visible: bare funnel under its header. Chip built first to host it.
    const chip = chipLabel && makeChip(doc, chipLabel);
    const wrap = popover(doc, `Filter ${cfg.label || col}`, panel => {
      const p = prof && profile(doc, data[col] || [], state);
      p && panel.append(p);
      // `box = FALSE` drops the expression box, limiting to the widget's choices
      if (cfg.box !== false) {
        const box = elem(doc, "input", {
          type: "search", className: "lti-search",
          "aria-label": `${cfg.label || col} filter expression`
        }, panel);
        const boxEd = { reflect: v => { if (doc.activeElement !== box) box.value = v; } },
              note = elem(doc, "div", { className: "lti-nl" }, panel);
        editors.push(boxEd);
        addTips(box, () => columnExamples(data[col]));
        // Plain-language conditions become one expression (`(x > 5) && (x < 9)`);
        // anything else stays as typed
        onType(box, v => {
          const t = Q.parse(v, {}, col), e = Q.expr(t);
          note.textContent = e && Q.parsed(t) ? Q.text(t, () => null) : "";
          setTerm(e ?? v.trim(), boxEd);
        });
      }
      const wEd = kind.build(doc, cfg, setTerm);  // widget as syncing editor
      editors.push(wEd);
      widget = elem(doc, "div", { className: "lti-widget" }, panel);
      widget.append(...[].concat(wEd.el));
      setTerm(kind.init(cfg), null);              // seed default
    }, () => showSummary(), chip && chip.el);      // refresh chip text on close
    // Active class tracks every change, but variable-width chip text would shift
    // the chip (and popover) mid-drag, so the summary waits for close.
    let root = wrap;
    if (chip) {
      chip.el.append(wrap);
      root = chip.el;
      mark = chip.mark;
      showSummary = () => chip.summarize(kind.describe(state.filters[col] || "", cfg));
    } else {
      mark = cur => root.classList.toggle("lti-on", !!cur);
    }
    mark(state.filters[col] || "");  // paint seeded term
    showSummary();
    return root;
  }

  // Head-bar chip per hidden typed column (see typedFilter).
  function addControlFilters(cell, barCols, cfg, data, state, refresh, prof) {
    const doc = cell.ownerDocument;
    for (const col of barCols)
      cell.append(
        typedFilter(doc, col, cfg[col], data, state, refresh, cfg[col].label || col, prof));
  }

  // Pager as the last <tfoot> row (after footnotes), plus a page-size <select> if
  // several sizes. Symbols/numbers only: « ‹ › » and `from–to / total`. Returns
  // the callback updating them for a new row count.
  function addPaginate(el, nCol, sizes, nRow, state, repage) {
    const doc = el.ownerDocument;
    let foot = el.tFoot;
    // reuse core footer so the pager matches its sizing
    if (!foot) (foot = el.createTFoot()).className = "lt-footer";
    const bar = elem(doc, "div", { className: "lti-pager" },
            fullRow(foot, "lti-pager-row", nCol, -1)),
          pos = elem(doc, "span", { className: "lti-pos" });
    state.pageSize = sizes[0];
    // pageSlice() clamps the last page, so any large number works
    const steps = [() => 0, p => p - 1, p => p + 1, () => 1e9];
    const btns = ["«", "‹", "›", "»"].map((glyph, i) => {
      const b = elem(doc, "button", {
        type: "button", textContent: glyph,
        "aria-label": ["First", "Previous", "Next", "Last"][i]
      }, bar);
      b.onclick = () => { state.page = steps[i](state.page); repage(); };
      return b;
    });
    bar.append(pos);
    // no dropdown if the smallest size holds every row
    if (sizes.length > 1 && nRow > Math.min(...sizes.filter(n => n > 0))) {
      const sel = elem(doc, "select", { "aria-label": "Rows per page" }, bar);
      // 0 = all rows (∞)
      sizes.forEach(n => elem(doc, "option", { value: n, textContent: n || "∞" }, sel));
      sel.onchange = () => { state.pageSize = +sel.value; state.page = 0; repage(); };
    }
    return total => {
      // size 0 = one page of everything
      const n = state.pageSize || total || 1,
            last = Math.max(0, Math.ceil(total / n) - 1),
            // when filtered, append full count in parens (no i18n)
            all = total < nRow ? ` (${nRow})` : "";
      pos.textContent = (total ?
        `${state.page * n + 1}–${Math.min(total, (state.page + 1) * n)} / ${total}` :
        "0 / 0") + all;
      btns.forEach((b, i) => b.disabled = i < 2 ? !state.page : state.page === last);
    };
  }

  // Enhance an opted-in table (idempotent via dataset flag).
  const onMount = (el, spec) => {
    if (!spec?.interactive || el.dataset.ltiOn) return;
    el.dataset.ltiOn = "1";
    enhance(el, spec);
  };

  LT.plugins.interactive = { matcher, computeView, pageSlice, enhance };
  // Reusable bits for callers' control-bar widgets (el._lt.bar): chip, popover,
  // checklist
  LT.ui = Object.assign(LT.ui || {}, { popover, checklist: makeChecklist, chip: makeChip });
  LT.onMount.push(onMount);
  // Core drains its queue before this loads, so the callback misses earlier
  // renders; enhance existing tables now. (Skipped without a DOM, e.g. Node tests.)
  if (typeof document !== "undefined")
    $$(document, ".lt-table").forEach(el => onMount(el, el._ltSpec));
})(typeof window !== "undefined" ? window : globalThis);
