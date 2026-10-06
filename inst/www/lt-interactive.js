/* lt-interactive.js — opt-in interactivity for lt tables (search, sort, column
 * filters, pagination, column resizing, column show/hide).
 *
 * A plugin on the existing LT global (see lt.js): it adds no new global. For a
 * table whose spec carries `interactive`, it adds the requested controls and
 * re-renders <tbody> through the core `spec._viewRows` seam. Every control is a
 * row of the table itself — the search box in <thead>, the pager in <tfoot> —
 * so it is exactly as wide as the table and scrolls with it. Row structure is
 * honored: separator row groups, indentation, and rowspan row groups all
 * sort/filter within each group or subtree, never across it (see computeView).
 */
(root => {
  "use strict";
  const LT = root.LT;
  // Bail out if core is absent or too old, or the plugin already loaded.
  if (!LT?.onMount || LT.plugins.interactive) return;

  const MIN_COL = 24;  // px: a dragged column never gets narrower than this
  let coll;  // locale-aware comparator, built on first use and reused
  // A column is numeric if its first non-null value is a number (how core
  // lt.js decides alignment and formatting).
  const numCol = col => typeof col.find(v => v != null) === "number";
  // A number as subscript digits (₁ ₂ …), for the sort-order ordinals.
  const sub = n => String(n).replace(/\d/g, d => "₀₁₂₃₄₅₆₇₈₉"[d]);
  // A sort key: a `"col"` (ascending) or `"-col"` (descending) string, or an
  // explicit `{col, dir}` object. Normalizes either to `{col, dir}`.
  const parseKey = k => typeof k !== "string" ? { ...k } :
    k[0] === "-" ? { col: k.slice(1), dir: "desc" } : { col: k, dir: "asc" };
  // Compare two non-null values: numeric subtraction for a numeric column, else
  // a locale-aware string compare (the collator built once, lazily reused).
  const cmpVals = (x, y, num) => {
    coll ||= new Intl.Collator();
    return num ? x - y : coll.compare(String(x), String(y));
  };

  // --- Small DOM helpers, so building the controls stays terse ---
  const $ = (el, sel) => el.querySelector(sel),
        $$ = (el, sel) => el.querySelectorAll(sel),
        on = (t, type, fn, opts) => t.addEventListener(type, fn, opts),
        off = (t, type, fn) => t.removeEventListener(type, fn);
  // A row's data cells, in column order: its children minus the leading rowspan
  // group-column cells (class `lt-row-group`), which are not in `spec._cols` and,
  // in rowspan mode, appear on some rows but not others (a run's later rows have
  // none). Selecting by class — not position — is what lets the positional code
  // (hide, detail, display capture) stay correct whatever leads the row.
  const dataCells = tr =>
    [...tr.children].filter(c => !c.classList.contains("lt-row-group"));
  // Create a <tag> and assign `props`: a dashed key ("aria-label") sets an
  // attribute, any other key ("className", "type", "textContent") a DOM
  // property. Appends to `parent` when given, and returns the new element.
  function elem(doc, tag, props = {}, parent) {
    const e = doc.createElement(tag);
    for (const k in props)
      k.includes("-") ? e.setAttribute(k, props[k]) : (e[k] = props[k]);
    return parent ? parent.appendChild(e) : e;
  }
  // Pointer-drag: after a pointerdown `e`, call `onMove(ev)` for every move until
  // pointerup, then `onEnd()` (if given). Shared by column resize and the range
  // filter's slider thumbs; suppresses text selection during the drag.
  function drag(e, onMove, onEnd) {
    e.preventDefault();
    const doc = e.target.ownerDocument || document, move = ev => onMove(ev);
    on(doc, "pointermove", move);
    on(doc, "pointerup", () => {
      off(doc, "pointermove", move);
      onEnd && onEnd();
    }, { once: true });
  }

  // Compile a search term into a predicate over one row's cells (`{raw, disp}`
  // objects), or null to keep every row. Ported from forestly's
  // inst/js/search-filter.js so results stay consistent across the projects.
  //  - Expression mode, when the term references the cell variable `x` (e.g.
  //    `x > 5`, `x !== "Rash"`): evaluated as JavaScript against the *raw*
  //    value, as a string and (when finite) as a number. A leading `!` or an
  //    `!=` is negation, which keeps a row only when *every* cell satisfies the
  //    test; otherwise *any* matching cell keeps the row.
  //  - Substring mode otherwise: case-insensitive match against the *display*
  //    text, with a leading `!` negating.
  function matcher(term) {
    const v = String(term ?? "").trim();
    if (v === "") return null;
    if (/(^|[^\w$])x([^\w$]|$)/.test(v)) {
      let fn;
      try { fn = new Function("x", `return (${v});`); } catch (e) {}
      if (fn) {
        const neg = /^\s*!|!=/.test(v), test = raw => {
          if (raw == null) return neg;
          try {
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

  // The view pipeline (pure — no DOM): per-column filters, the table-wide
  // search, then any externally registered predicates, then sort, yielding the
  // 1-based original row indices for `spec._viewRows`. `disp[col][i]` is a
  // cell's displayed text (what substring search matches); `state` holds the
  // filter terms (`filters[col]`), the search term, the predicates
  // (`predicates`, keyed by id — see el._lt.filter), and the sort keys (`sort`,
  // an array of `{col, dir}` applied in order). Filters, the search, and the
  // predicates are combined with AND: a row must pass all of them.
  function computeView(spec, disp, state) {
    const cols = spec._cols || [], data = spec.data || {},
          nRow = (data[cols[0]] || []).length,
          cell = (c, r) => ({
            raw: data[c]?.[r - 1] ?? null, disp: disp[c]?.[r - 1] ?? ""
          });

    // The per-row keep test: the column filters, the table-wide search, then the
    // externally registered predicates, combined with AND (a row must pass all).
    // A filter looks at one cell, so the cheap tests come first.
    const tests = [];
    for (const c in state.filters || {}) {
      const pred = matcher(state.filters[c]);
      if (pred) tests.push(r => pred([cell(c, r)]));
    }
    const sPred = matcher(state.term);
    if (sPred) tests.push(r => sPred(cols.map(c => cell(c, r))));
    // predicates registered from outside (el._lt.filter) run last, each a
    // function of the row's raw values keyed by column. The row carries *every*
    // column (not just the visible `cols`), so a widget can filter on a hidden
    // helper column — e.g. forestly's incidence slider reads the hidden
    // `hide_prop`, its parameter dropdown the hidden `parameter`.
    const fns = Object.values(state.predicates || {});
    if (fns.length) {
      const all = Object.keys(data),
            row = r => Object.fromEntries(all.map(c => [c, data[c]?.[r - 1] ?? null]));
      tests.push(r => { const o = row(r); return fns.every(f => f(o)); });
    }
    const keep = r => tests.every(t => t(r));

    // Build a comparator from a list of sort keys: each key in turn, falling
    // through to the next on a tie; a key's column (resolved once) carries its
    // numeric test and direction. nulls sort last regardless of direction, so the
    // direction never applies to them. Null when the list sorts nothing.
    const makeCmp = sortKeys => {
      const keys = sortKeys.map(k => {
        const col = data[k.col];
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

    // Reduce a list of rows (in document order) to the kept rows in view order,
    // sorted by `cmp`. With no indentation this is a plain filter + sort. With
    // indentation the rows form a tree (a row's parent is the nearest earlier row
    // one level up): filtering keeps any row with a surviving descendant, so a
    // match stays in context, and a sort reorders siblings while each subtree
    // travels with its parent.
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

    // Rowspan row groups: the group columns (outermost first) nest, so the view
    // must stay a hierarchy — sorting a data column may only reorder rows within
    // the innermost group, never across a group boundary, or a spanning cell
    // would have to split. So partition by group column 1, then recurse on
    // column 2 within each block, …, and only at the leaves sort by the data
    // keys. A group column the reader clicked orders its blocks by that column
    // (its key is pulled out of the leaf sort); untouched, blocks keep their
    // first-appearance order. Rendering recomputes the spans from this order.
    const gcols = spec._rowspan;
    if (gcols) {
      const dir = {}, leaf = [];
      for (const k of state.sort || [])
        gcols.includes(k.col) ? (dir[k.col] = k.dir) : leaf.push(k);
      const leafCmp = makeCmp(leaf);
      const partition = (rows, depth) => {
        if (depth === gcols.length) return reduce(rows, leafCmp);
        const col = data[gcols[depth]], blocks = new Map();
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

    // Separator row groups keep their place (the group is the unit that does not
    // move): each group's rows filter/sort within it, and the surviving rows of
    // all groups concatenate in group order, then any ungrouped rows (manual
    // groups need not cover every row). A group left with no row simply
    // contributes nothing — its header is re-emitted at render only when a row
    // remains.
    const cmp = makeCmp(state.sort || []);
    const groups = spec._groups;
    if (!groups) return reduce(all(), cmp);
    const grouped = new Set(), out = [];
    for (const g of groups) { g.rows.forEach(r => grouped.add(r)); out.push(...reduce(g.rows, cmp)); }
    const rest = [];
    for (let r = 1; r <= nRow; r++) if (!grouped.has(r)) rest.push(r);
    return [...out, ...reduce(rest, cmp)];
  }

  // The rows of `view` on the current page. `state.page` is clamped into range
  // first (in place, so the pager reads back the page actually shown): the row
  // count shrinks as filters are typed. A `state.pageSize` of 0 means every row
  // on one page.
  function pageSlice(view, state) {
    const n = state.pageSize;
    if (!n) { state.page = 0; return view; }
    const last = Math.max(0, Math.ceil(view.length / n) - 1);
    state.page = Math.min(Math.max(state.page || 0, 0), last);
    return view.slice(state.page * n, (state.page + 1) * n);
  }

  // Displayed text per column, keyed to the original row order. It does not
  // change with the view, so capture it once from the initial full render.
  // `order[i]` is the original 1-based index of the i-th body row as rendered
  // (for a grouped table whose groups do not follow file order); absent ⇒ body
  // rows are in index order. Separator group-header rows are skipped — they are
  // no column's cell. `dataCells` drops any leading rowspan group cell, so the
  // index lines up with `cols` whatever precedes the data cells.
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
          // each row's group (for re-emitting a surviving header), and the body
          // render order: groups in order, then any ungrouped rows (so a manual
          // group listed out of file order maps the display text correctly)
          groupOf = {}, order = groups ? [] : null;
    if (groups) {
      const seen = new Set();
      groups.forEach(g => g.rows.forEach(r => { groupOf[r] = g; order.push(r); seen.add(r); }));
      for (let r = 1; r <= nRow; r++) if (!seen.has(r)) order.push(r);
    }
    // turn a page's data rows into the row list core renders: a group header
    // (an object core draws as a full-width label row) is inserted whenever the
    // group changes, so a group spanning a page boundary re-shows its header at
    // the top of the next page; ungrouped rows get none.
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
    // the rowspan group columns lead the header row (they are hidden from
    // `cols`); the full header order drives sort, so clicking a group header
    // reorders its blocks (computeView pulls a group-column key out of the leaf
    // sort — see the `_rowspan` branch there)
    const nGroup = spec._rowspan ? spec._rowspan.length : 0,
          allCols = nGroup ? [...spec._rowspan, ...cols] : cols,
          // the table's full column count: a full-width row (control bar, pager,
          // no-match placeholder, detail) must span the leading group columns too
          nAll = nGroup + cols.length;
    const disp = captureDisplay(el, cols, order),
          // the bottom header row: the one whose cells line up with `cols`
          hrow = [...$$(el, "thead tr")].pop(),
          // an array `sort` on the options is an initial sort (a list of key
          // strings or objects, see parseKey); `true` just turns sorting on
          state = {
            filters: {}, predicates: {}, page: 0, pageSize: 0,
            sort: Array.isArray(opts.sort) ? opts.sort.map(parseKey) : []
          };
    let view,          // filtered + sorted indices, cached across page turns
        sync = () => {};  // pager readout, replaced by addPaginate()
    // hooks run on each freshly-built <tbody>, in order, to re-assert the state a
    // swap drops: expand carets / detail rows (addDetail), the hidden cells of a
    // column turned off in the column menu (addColumnToggle). Each gets the new
    // <tbody> and its row indices.
    const postSwap = [];

    // `stale` means the view itself changed (a term or the sort), as opposed to
    // only the page: recompute it and go back to the first page.
    const refresh = (stale = true) => {
      if (stale) { view = computeView(spec, disp, state); state.page = 0; }
      const rows = pageSlice(view, state),
            // _viewRows carries the page's data rows with group headers spliced
            // back in; postSwap hooks get the same list, one entry per <tbody> row
            vr = withGroups(rows),
            tmp = elem(el.ownerDocument, "template", {
              innerHTML: LT.buildHtml({ ...spec, _viewRows: vr })
            });
      const body = $(tmp.content, "tbody");
      if (!rows.length)  // no matches: a neutral symbol spanning all columns
        body.innerHTML = `<tr class="lti-empty"><td colspan="${nAll}">—</td></tr>`;
      else postSwap.forEach(f => f(body, vr));
      $(el, "tbody").replaceWith(body);
      sync(view.length);
    };

    // a small controller for driving the table from outside (e.g. forestly's
    // own dropdown and range-slider widgets): register a predicate over a row's
    // raw values (`{col: value}`, including hidden columns) under an id,
    // replacing or (with a null `fn`) removing it, then re-render. `spec`/`state`
    // are exposed for reading (a widget's choices come from `el._ltSpec.data`).
    el._lt = {
      spec, state,
      refresh: () => refresh(),
      // the current filtered + sorted row indices (1-based, every row, not just
      // the page) — e.g. for a "download what's shown" button that must honor the
      // typed filters (which live in state.filters, not external predicates)
      view: () => view || computeView(spec, disp, state),
      filter(id, fn) {
        fn ? (state.predicates[id] = fn) : (delete state.predicates[id]);
        refresh();
      }
    };

    // the `filter` option is normalized (R side) to { default?, cols? }: a
    // `default` spec applies to every visible column left unnamed, `cols` maps a
    // column to its spec (`true` = a plain box, else a typed select/range). A
    // typed filter on a hidden column (not in `cols` = spec._cols) can't live
    // under a header, so it becomes a chip in the head bar; everything else sits
    // under its column header.
    const flt = opts.filter,
          barCols = flt?.cols ?
            Object.keys(flt.cols).filter(c => flt.cols[c] !== true && !cols.includes(c)) : [];
    // the table-wide controls share one full-width head row, laid out left to
    // right: an icon group (the column menu and the download button), then the
    // head-bar filter chips, then the search box (which absorbs the free space)
    const headBar = (opts.search !== false || opts.hide || barCols.length || opts.download) ?
      elem(el.ownerDocument, "div", { className: "lti-bar" },
        fullRow(el.tHead || el.createTHead(), "lti-head", nAll, 0)) : null;
    // the data-column header labels (skipping any leading group cell), read
    // before sort/resize decorate the cells, so the column menu can list the
    // displayed labels rather than the raw names
    const labels = dataCells(hrow).map(th => th.textContent);
    // wire sort before adding the filter row, so it sees the header row only;
    // `allCols` so every header cell binds (a group header is sortable too)
    if (opts.sort !== false) addSort(hrow, allCols, state, refresh);
    // the under-header filter row: needed when a default applies to visible
    // columns or any named column is itself visible
    if (flt && (flt.default || (flt.cols && Object.keys(flt.cols).some(c => cols.includes(c)))))
      addFilter(hrow, cols, flt, spec.data, state, refresh);
    const layout = opts.resize ? fixedLayout(el, hrow, cols.length, nGroup) : null;
    if (opts.resize) addResize(el, layout);
    // the icon buttons sit together in a group that keeps its natural width;
    // append them (menu first, download second) before the chips and search so
    // the DOM order is the visual order
    const icons = (opts.hide || opts.download) ?
      elem(el.ownerDocument, "div", { className: "lti-icons" }, headBar) : null;
    if (opts.hide)
      addColumnToggle(icons, el, hrow, cols, labels, opts.hide, layout, postSwap);
    if (opts.download) addDownload(icons, el, spec, cols, labels, opts.download);
    // the chips share a group so the bar has three parts (icons, chips, search)
    // with a wider gap between them than within each
    if (barCols.length) addControlFilters(
      elem(el.ownerDocument, "div", { className: "lti-chips" }, headBar),
      barCols, flt.cols, spec.data, state, refresh);
    if (opts.search !== false) addSearch(headBar, el, state, refresh);
    // row detail re-renders through the same seam: toggling a row only changes
    // which rows carry a detail block, so a plain re-render (no new view) is
    // enough
    if (opts.detail)
      postSwap.push(addDetail(el, spec, nAll, state, opts.detail, () => refresh(false)));
    // `pager` is the page sizes to offer, the first one being the initial
    if (opts.pager) {
      const sizes = Array.isArray(opts.pager) ? opts.pager : [10, 25, 50, 100];
      sync = addPaginate(el, nAll, sizes, nRow, state, () => refresh(false));
      refresh();  // cut the full render down to the first page
    } else if (state.sort.length || opts.detail) {
      // core rendered the rows in file order; re-render to apply an initial
      // sort and/or to add the expand carets
      refresh();
    }
  }

  // A search input: `type="search"` lets the browser supply the affordance (and
  // a clear button), so there is no icon or placeholder text to translate; the
  // label is for screen readers only.
  function searchInput(doc, label) {
    return elem(doc, "input", {
      type: "search", className: "lti-search", "aria-label": label
    });
  }

  // A full-width row of the table, for a control that belongs to the table as a
  // whole. Living inside the table (instead of beside it) is what keeps the
  // controls exactly as wide as the table, however narrow that is, and keeps
  // everything inside the core `.lt-wrap` scroll box. Returns its single cell.
  function fullRow(sect, cls, nCol, pos) {
    const row = sect.insertRow(pos);
    row.className = cls;
    return elem(sect.ownerDocument, "td", { colSpan: nCol }, row);
  }

  // Debounce typing so a long list is not re-rendered per keystroke; Enter (or
  // leaving the box) applies at once.
  function onType(input, apply) {
    let timer;
    const go = () => apply(input.value);
    input.oninput = () => { clearTimeout(timer); timer = setTimeout(go, 150); };
    input.onchange = () => { clearTimeout(timer); go(); };
  }

  // Table-wide search box, appended to the shared head cell.
  function addSearch(cell, el, state, refresh) {
    const input = cell.appendChild(searchInput(el.ownerDocument, "Search"));
    onType(input, v => { state.term = v; refresh(); });
  }

  // Escape one value for a CSV field: wrap in quotes (doubling any inside) only
  // when it holds a comma, quote, or newline, so plain values stay bare.
  function csvField(v) {
    const s = v == null ? "" : String(v);
    return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  }

  // A button that downloads the table's current view as a CSV file. The header
  // row is the column labels; each body row is a view row (every row the filters
  // and search keep, in sort order, across all pages — `el._lt.view()` gives the
  // 1-based original indices) rendered with the displayed cell text from
  // `spec._display`. `name` is the file name (`true` = a default); group columns
  // (null in `cols`) are skipped. No library, no network: a Blob and an <a>.
  function addDownload(cell, el, spec, cols, labels, name) {
    const doc = el.ownerDocument,
          file = (typeof name === "string" && name ? name : "table")
            .replace(/(\.csv)?$/i, ".csv"),
          keep = cols.map((c, i) => i).filter(i => cols[i] != null),
          btn = elem(doc, "button", {
            type: "button", className: "lti-download", title: "Download CSV",
            "aria-label": "Download table as CSV"
          }, cell);
    btn.onclick = () => {
      const disp = spec._display || {},
            lines = [keep.map(i => csvField(labels[i] ?? cols[i])).join(",")];
      for (const r of el._lt.view())
        lines.push(keep.map(i => csvField((disp[cols[i]] || [])[r - 1])).join(","));
      const url = URL.createObjectURL(
        new Blob([lines.join("\n")], { type: "text/csv" }));
      elem(doc, "a", { href: url, download: file }).click();
      URL.revokeObjectURL(url);
    };
  }

  // Advance one column through asc → desc → unsorted, updating `state.sort` (an
  // ordered list of `{col, dir}` keys). A plain click sorts by that column
  // alone; a shift-click adds it as a further tie-breaker (or re-cycles it where
  // it already is), so several columns can sort together.
  function cycle(state, col, additive) {
    const order = (state.sort || []).slice(),
          i = order.findIndex(k => k.col === col),
          dir = i < 0 ? "asc" : order[i].dir === "asc" ? "desc" : null;
    if (!additive) { state.sort = dir ? [{ col, dir }] : []; return; }
    if (i < 0) order.push({ col, dir });        // dir is "asc" here
    else if (dir) order[i] = { col, dir };
    else order.splice(i, 1);
    state.sort = order;
  }

  // Click-to-sort headers (shift-click to sort by several at once). The
  // indicators and aria-sort live on the <th>s, which survive the <tbody> swap,
  // so repainting them needs no re-render. An ordinal (₁ ₂ …) marks each key's
  // place when more than one column sorts.
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
      // sort on the label only, not the whole cell, so the resize grip (a <th>
      // child outside the label) stays unclickable for sorting
      const lab = elem(doc, "span", { className: "lti-label" }, th);
      while (th.firstChild !== lab) lab.append(th.firstChild);
      marks[col] = { th, ind: elem(doc, "span", { className: "lti-sort" }, lab) };
      lab.onclick = e => { cycle(state, col, e.shiftKey); paint(); refresh(); };
    });
    paint();  // reflect any initial sort carried on the spec
  }

  // A row of per-column filters below the headers, inside <thead> so the <tbody>
  // swap leaves it (and what has been typed into it) alone. `flt` is the
  // normalized { default?, cols? }: each visible column takes its named spec, or
  // the default when unnamed. A `true` spec is a plain search box; a typed spec
  // is a funnel + popover under the header (see typedFilter).
  function addFilter(hrow, cols, flt, data, state, refresh) {
    const doc = hrow.ownerDocument,
          row = elem(doc, "tr", { className: "lti-filters" }),
          def = flt.default, explicit = flt.cols || {};
    cols.forEach(c => {
      const cell = elem(doc, "td", {}, row),
            spec = c in explicit ? explicit[c] : def;
      if (!spec) return;                           // no filter on this column
      if (spec === true) {                         // a plain search box
        const input = cell.appendChild(searchInput(doc, `Filter ${c}`));
        onType(input, v => { v ? (state.filters[c] = v) : delete state.filters[c]; refresh(); });
      } else                                       // a typed funnel under the header
        cell.appendChild(typedFilter(doc, c, spec, data, state, refresh, null));
    });
    hrow.parentNode.appendChild(row);
  }

  // Expandable row detail. `detailOpt` is either an array of column names (the
  // detail is a one-row table of those columns' displayed values) or a callback
  // `(rawRow, index, displayedRow) => spec` (or the name of such a global one),
  // called the first time a row is expanded (and cached) to build the spec for
  // its drop-down detail table. Returns a
  // `decorate(body, rows)` that each <tbody> re-render runs: it prepends an
  // expand caret to every row and, after each open row, inserts a full-width
  // detail row rendered through LT.render (so a detail table can itself be
  // interactive). Expanded rows are tracked by their original index, so detail
  // follows its row across sort/filter/page. Resolving `detailOpt` is deferred
  // to the first expand, so a global built after the table still works.
  function addDetail(el, spec, nCol, state, detailOpt, rerender) {
    // `nCol` is the table's full width, so the detail row spans the leading
    // rowspan group columns too
    const doc = el.ownerDocument, cache = {};
    state.expanded = new Set();
    // a row as an object keyed by column (every column, including ones hidden
    // from the table), built from `src`: spec.data gives raw values, spec._display
    // the formatted text the table shows
    const pick = (src, r) => {
      const o = {}; for (const c in src) o[c] = src[c]?.[r - 1] ?? null; return o;
    };
    const build = r => {
      if (r in cache) return cache[r];
      const disp = pick(spec._display || {}, r);
      let out = null;
      if (Array.isArray(detailOpt)) {
        // a list of column names: show those columns' displayed values as a
        // one-row table (the columns can be ones hidden from the main table)
        const data = {};
        for (const c of detailOpt) data[c] = [disp[c] ?? null];
        out = { data };
      } else {
        // a callback (or the name of one): (raw row, index, displayed row)
        const fn = typeof detailOpt === "function" ? detailOpt : root[detailOpt];
        if (typeof fn === "function") out = fn(pick(spec.data || {}, r), r, disp);
      }
      return cache[r] = out;
    };
    const toggle = r => {
      state.expanded.has(r) ? state.expanded.delete(r) : state.expanded.add(r);
      rerender();
    };
    return (body, rows) => [...body.rows].forEach((tr, i) => {
      const r = rows[i];
      if (typeof r !== "number") return;  // a separator group-header row
      // the first data cell (past any leading rowspan group cell), so the caret
      // sits in the row's own first column, not a group label
      const td0 = dataCells(tr)[0], open = state.expanded.has(r);
      if (!td0) return;
      const btn = elem(doc, "button", {
        type: "button", className: "lti-expand", textContent: open ? "▾" : "▸",
        "aria-expanded": String(open), "aria-label": "Toggle detail"
      });
      btn.onclick = () => toggle(r);
      td0.prepend(btn);
      const child = open && build(r);
      if (child) {
        const row = elem(doc, "tr", { className: "lti-detail" });
        tr.after(row);
        const cell = elem(doc, "td", { colSpan: nCol }, row);
        LT.render(elem(doc, "div", {}, cell), child);
      }
    });
  }

  // The table's <colgroup>, created when core emitted none (it only does so for
  // a table given explicit widths on the R side). It gets `nGroup` leading <col>s
  // for the rowspan group columns (which lead each header/body row) then one per
  // data column, matching core's own layout so widths line up.
  function colGroup(el, nCol, nGroup = 0) {
    let g = $(el, "colgroup");
    if (!g) {
      const doc = el.ownerDocument;
      g = elem(doc, "colgroup");
      for (let i = 0; i < nGroup + nCol; i++) elem(doc, "col", {}, g);
      // <colgroup> comes after <caption> (the title), before <thead>
      el.caption ? el.caption.after(g) : el.prepend(g);
    }
    return [...g.children];
  }

  // Fixed-layout machinery for column resize. The widths live on the
  // <colgroup>, outside <tbody>, so they survive every
  // re-render. `freeze()` switches the table to fixed layout once, pinning every
  // column at the width it has then, so a later width change moves that one
  // column instead of reflowing the whole table. `natural(i)` is column i's
  // content width (an unconstrained reflow, with the widths put back after).
  // `setWidth(i, w, min)` sets column i to `w` px (clamped to `min`), widening or
  // narrowing the table by as much; the other columns keep their widths.
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
    // `dataCs` drops the leading group <col>s, so a data-column consumer (the
    // column-hide menu) indexes it by data-column position
    return { ths, cs, dataCs: cs.slice(nGroup), freeze, natural, setWidth };
  }

  // Drag-to-resize column edges: a grip on the right edge of each header cell.
  // On the first drag the table switches to fixed layout (see fixedLayout) so
  // that dragging one edge moves it alone. A double-click fits the column to its
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
        // no label floor: omit setWidth's min arg to take its default, and the
        // cell clips its overflow (CSS) instead of spilling when shrunk
        drag(e, ev => setWidth(i, w0 + ev.clientX - x0),
          () => el.classList.remove("lti-resizing"));
      };
    });
  }

  // Column-visibility menu: an eye button at the start of the head cell that
  // opens a checklist, one box per column. Unchecking a column hides it
  // outright — its header and every body cell take the `hidden` attribute (which
  // a <tbody> swap drops, so it is re-applied via postSwap). Every column is
  // listed; `opt` is `true` (all start shown) or `{ hidden: [...] }` (those names
  // start hidden). `layout` is resize's fixed layout, used when present to drop a
  // hidden column's <col> so the fixed table reflows too.
  function addColumnToggle(cell, el, hrow, cols, labels, opt, layout, postSwap) {
    const doc = el.ownerDocument,
          start = (opt && opt.hidden) || [], hidden = new Set();
    // show/hide column i's cell in one row (indexing the row's data cells, past
    // any leading rowspan group cell), skipping the single colspan cell of a
    // detail or empty row (which spans every column and is no column's own)
    const setCell = (tr, i, on) => {
      const c = dataCells(tr)[i];
      if (c && c.colSpan === 1) c.hidden = on;
    };
    // re-hide every hidden column's cells on each freshly-built <tbody>
    postSwap.push(body => hidden.forEach(i => {
      for (const tr of body.rows) setCell(tr, i, true);
    }));
    // show/hide column i everywhere it lives: the <col> (fixed layout only) and,
    // one row at a time, every per-column cell — the header labels, the filter
    // boxes, the body cells, and a plot's axis footer. The spanner row is the one
    // row whose merged cells break the 1:1 column-to-cell index, so skip it; the
    // setCell colspan guard skips the other full-width rows (search bar, detail,
    // footnotes, pager). <thead>/<tfoot> survive a <tbody> swap, so this one pass
    // keeps them in sync; only the fresh <tbody> is re-hidden (via postSwap).
    const apply = i => {
      const on = hidden.has(i);
      if (layout?.dataCs[i]) layout.dataCs[i].hidden = on;
      for (const tr of el.rows)
        if (!tr.classList.contains("lt-spanner-row")) setCell(tr, i, on);
    };
    const wrap = elem(doc, "span", { className: "lti-cols" }, cell),
          btn = elem(doc, "button", {
            type: "button", title: "Columns",
            "aria-label": "Show or hide columns", "aria-expanded": "false"
          }, wrap),
          menu = elem(doc, "div", { className: "lti-menu", hidden: true }, wrap);
    cols.forEach((c, i) => {
      if (c == null) return;
      const label = elem(doc, "label", {}, menu),
            box = elem(doc, "input", { type: "checkbox", checked: true }, label);
      label.append(labels[i] ?? c);
      if (start.includes(c)) { box.checked = false; hidden.add(i); }
      box.onchange = () => {
        box.checked ? hidden.delete(i) : hidden.add(i);
        apply(i);
      };
    });
    cols.forEach((_, i) => apply(i));  // reflect any columns that start hidden
    const open = on => {
      menu.hidden = !on;
      btn.setAttribute("aria-expanded", String(on));
    };
    btn.onclick = e => { e.stopPropagation(); open(menu.hidden); };
    on(doc, "click", e => { if (!wrap.contains(e.target)) open(false); });
    on(doc, "keydown", e => { if (e.key === "Escape") open(false); });
  }

  // --- Typed column filters (the `filter` named-list form). A typed spec is
  // {type:"select"|"range", label?, choices?, min?, max?, step?, value?,
  // selected?}; it renders as a funnel + popover, under its own header when the
  // column is visible or as a labelled head-bar chip when it is hidden (the
  // column still travels in spec.data, which is what computeView filters on). The
  // popover holds an expression box AND a widget (a value dropdown or a range
  // slider); both edit the one filter term for that column (state.filters[col])
  // and stay in sync, so the widget is a friendly face on the same expression a
  // reader could type.

  // A filter term string <-> a widget value, per type. A `null` parse means the
  // term is something the widget can't show (a hand-typed expression), so the
  // widget falls back to neutral and the box stays authoritative.
  const selExpr = v => v === "" ? "" : `x == ${JSON.stringify(String(v))}`,
        selParse = s => {
          const m = /^\s*x\s*==\s*(['"])([\s\S]*)\1\s*$/.exec(s || "");
          return m ? m[2] : null;
        },
        rngExpr = (lo, hi, min, max) =>
          lo <= min && hi >= max ? "" : `x >= ${lo} && x <= ${hi}`,
        rngParse = s => {
          const m = /^\s*x\s*>=\s*(-?[\d.]+)\s*&&\s*x\s*<=\s*(-?[\d.]+)\s*$/.exec(s || "");
          return m ? [parseFloat(m[1]), parseFloat(m[2])] : null;
        };

  // Fill a typed spec's choices (select) or min/max (range) from the column's
  // data when the R side left them out, so `filter = list(x = "select")` needs no
  // enumeration. Returns a copy with the gaps filled.
  function resolveSpec(spec, column) {
    if (spec.type === "select") {
      let choices = spec.choices;
      if (!choices) {
        const seen = new Set(), vals = [];
        for (const v of column) if (v != null && !seen.has(v)) { seen.add(v); vals.push(v); }
        vals.sort((a, b) => typeof a === "number" && typeof b === "number"
          ? a - b : String(a).localeCompare(String(b)));
        choices = vals.map(v => ({ value: String(v), label: String(v) }));
      }
      // a leading blank is the "no filter" choice, so a select shows every row
      // until the reader picks a value (and can always return to it)
      if (!choices.some(o => o.value === "")) choices = [{ value: "", label: "" }, ...choices];
      return { ...spec, choices };
    }
    let { min, max } = spec;
    if (min == null || max == null) {
      let lo = Infinity, hi = -Infinity;
      for (const v of column) {
        const n = Number(v);
        if (isFinite(n)) { if (n < lo) lo = n; if (n > hi) hi = n; }
      }
      if (min == null) min = isFinite(lo) ? lo : 0;
      if (max == null) max = isFinite(hi) ? hi : 1;
    }
    return { ...spec, min, max };
  }

  // A dropdown of {value, label} options; `onInput(value)` fires on change.
  function makeSelect(doc, options, onInput) {
    const sel = elem(doc, "select", { className: "lti-filter-pick" });
    options.forEach(o => elem(doc, "option", { value: o.value, textContent: o.label }, sel));
    sel.onchange = () => onInput(sel.value);
    return { el: sel, set: v => sel.value = v };
  }

  // A two-thumb range slider from a track, a fill band, and two <button> thumbs —
  // no native <input type=range>, so no vendor pseudo-element CSS and no stacked-
  // input z-index hacks. Thumbs drag via the shared drag() helper and step with
  // the arrow keys (Home/End jump to the ends); the low thumb never passes the
  // high one. `cfg` is {min, max, step}; `onInput([lo, hi])` fires as a thumb
  // moves. Returns { el, set([lo, hi]) }.
  function makeSlider(doc, cfg, onInput) {
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
          setOne = (i, v) => {
            val[i] = snap(v);
            if (val[0] > val[1]) val = [Math.min(...val), Math.max(...val)];
            paint();
            onInput(val.slice());
          };
    thumbs.forEach((t, i) => {
      const at = clientX => {
        const r = track.getBoundingClientRect();
        return min + span * Math.min(1, Math.max(0, (clientX - r.left) / r.width));
      };
      t.onpointerdown = e => { t.focus(); drag(e, ev => setOne(i, at(ev.clientX))); };
      t.onkeydown = e => {
        const d = { ArrowLeft: -1, ArrowDown: -1, ArrowRight: 1, ArrowUp: 1 }[e.key];
        if (d) setOne(i, val[i] + d * step);
        else if (e.key === "Home") setOne(i, min);
        else if (e.key === "End") setOne(i, max);
        else return;
        e.preventDefault();
      };
    });
    paint();
    return { el: track, set: v => { val = v.slice(); paint(); } };
  }

  // A funnel button that toggles a floating panel built by `build(panel)`; closes
  // on an outside click or Escape. Returns the wrapper element.
  function popover(doc, label, build, onClose) {
    const wrap = elem(doc, "span", { className: "lti-pop" }),
          btn = elem(doc, "button", {
            type: "button", className: "lti-funnel", title: label,
            "aria-label": label, "aria-expanded": "false"
          }, wrap),
          panel = elem(doc, "div", { className: "lti-pop-panel", hidden: true }, wrap);
    build(panel);
    // keep the panel inside the table's scroll box: it opens to the funnel's left
    // edge by default, but a funnel near the right edge would push it past the
    // box (raising its horizontal scrollbar), so anchor it to the funnel's right
    // instead. The limit is the scroll box's right edge, not the viewport's — the
    // box can have room on screen yet none of its own, and vice versa.
    const place = () => {
      panel.style.left = panel.style.right = "";  // back to the CSS default (left:0)
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
    btn.onclick = e => { e.stopPropagation(); open(panel.hidden); };
    on(doc, "click", e => { if (!wrap.contains(e.target)) open(false); });
    on(doc, "keydown", e => { if (e.key === "Escape") open(false); });
    return wrap;
  }

  // One bundle per filter type, so adding a type is a single entry rather than a
  // branch in each of describe/build/init. `describe(term, cfg)` is the chip's
  // one-line summary; `init(cfg)` is the term for the configured default; and
  // `build(doc, cfg, setTerm)` makes the widget as a syncing editor `{ el,
  // reflect(term) }`, where `el` (a node or array of nodes) goes in the popover
  // and the widget's own input writes the term through `setTerm`. The term <->
  // value primitives (selExpr etc., above) back these.
  const KINDS = {
    select: {
      describe: (t, cfg) => {
        const v = selParse(t);
        if (v == null) return t ? "⋯" : "";
        const o = cfg.choices.find(o => o.value === v);
        return o ? o.label : v;
      },
      init: cfg => selExpr(cfg.selected ?? ""),
      build: (doc, cfg, setTerm) => {
        const w = makeSelect(doc, cfg.choices, v => setTerm(selExpr(v), ed)),
              ed = { el: w.el, reflect: t => { const v = selParse(t); w.set(v == null ? "" : v); } };
        return ed;
      }
    },
    range: {
      describe: t => { const p = rngParse(t); return p ? `${p[0]} – ${p[1]}` : t ? "⋯" : ""; },
      init: cfg => cfg.value ? rngExpr(cfg.value[0], cfg.value[1], cfg.min, cfg.max) : "",
      build: (doc, cfg, setTerm) => {
        const out = elem(doc, "span", { className: "lti-slider-out" }),
              show = p => out.textContent = `${p[0]} – ${p[1]}`,
              w = makeSlider(doc, cfg, v => { show(v); setTerm(rngExpr(v[0], v[1], cfg.min, cfg.max), ed); }),
              ed = { el: [w.el, out], reflect: t => { const p = rngParse(t) || [cfg.min, cfg.max]; w.set(p); show(p); } };
        return ed;
      }
    }
  };

  // Build one typed column filter and return its element. The funnel + popover
  // machinery is shared by both placements: a head-bar chip when `chipLabel` is a
  // string (a label + current-value summary wrap the funnel), or a bare funnel
  // under the column header when `chipLabel` is null.
  function typedFilter(doc, col, spec, data, state, refresh, chipLabel) {
    const cfg = resolveSpec(spec, data[col] || []),
          kind = KINDS[cfg.type],
          editors = [];       // the expression box + widget, kept in sync
    let mark = () => {};       // paints the active state once `root` exists (below)
    // set the one term, re-render, and reflect it into every editor but the one
    // that caused the change (`from`), so the slider and box update each other
    const setTerm = (expr, from) => {
      expr ? (state.filters[col] = expr) : delete state.filters[col];
      refresh();
      const cur = state.filters[col] || "";
      editors.forEach(e => e !== from && e.reflect(cur));
      mark(cur);
    };
    const wrap = popover(doc, `Filter ${cfg.label || col}`, panel => {
      const box = elem(doc, "input", {
        type: "search", className: "lti-search",
        "aria-label": `${cfg.label || col} filter expression`
      }, panel);
      const boxEd = { reflect: v => { if (doc.activeElement !== box) box.value = v; } };
      editors.push(boxEd);
      onType(box, v => setTerm(v.trim(), boxEd));
      const wEd = kind.build(doc, cfg, setTerm);  // the widget as a syncing editor
      editors.push(wEd);
      panel.append(...[].concat(wEd.el));
      setTerm(kind.init(cfg), null);              // seed the configured default
    }, () => showSummary());                       // refresh the chip text on close
    // a hidden column wraps the funnel in a chip (label + value summary); a
    // visible column shows the bare funnel under its own header
    let root = wrap, summary;
    if (chipLabel != null) {
      root = elem(doc, "span", { className: "lti-chip" });
      elem(doc, "span", { className: "lti-chip-name", textContent: chipLabel }, root);
      summary = elem(doc, "span", { className: "lti-chip-cur" }, root);
      root.appendChild(wrap);
    }
    // the active-state class tracks every change (color only, no reflow), but the
    // chip's value text is a variable width, so a live update while dragging the
    // slider would shift the funnel (and its popover) sideways; defer it to close
    mark = cur => root.classList.toggle("lti-on", !!cur);
    const showSummary = () =>
      summary && (summary.textContent = kind.describe(state.filters[col] || "", cfg));
    mark(state.filters[col] || "");  // paint the seeded term
    showSummary();
    return root;
  }

  // A head-bar chip for each hidden typed column (see typedFilter).
  function addControlFilters(cell, barCols, cfg, data, state, refresh) {
    const doc = cell.ownerDocument;
    for (const col of barCols)
      cell.appendChild(
        typedFilter(doc, col, cfg[col], data, state, refresh, cfg[col].label || col));
  }

  // Pager as the last row of <tfoot> (after any footnotes), with a page-size
  // <select> when there is more than one size to offer. Both are symbols or
  // numbers only: « ‹ › » for first/previous/next/last and `from–to / total`
  // for the position. Returns the callback that updates them for a new row
  // count.
  function addPaginate(el, nCol, sizes, nRow, state, repage) {
    const doc = el.ownerDocument;
    let foot = el.tFoot;
    // reuse the core footer if there is one, so the pager is sized like it
    if (!foot) (foot = el.createTFoot()).className = "lt-footer";
    const bar = elem(doc, "div", { className: "lti-pager" },
            fullRow(foot, "lti-pager-row", nCol, -1)),
          pos = elem(doc, "span", { className: "lti-pos" });
    state.pageSize = sizes[0];
    // the last page is clamped by pageSlice(), so a large number will do
    const steps = [() => 0, p => p - 1, p => p + 1, () => 1e9];
    const btns = ["«", "‹", "›", "»"].map((glyph, i) => {
      const b = elem(doc, "button", {
        type: "button", textContent: glyph,
        "aria-label": ["First", "Previous", "Next", "Last"][i]
      }, bar);
      b.onclick = () => { state.page = steps[i](state.page); repage(); };
      return b;
    });
    bar.appendChild(pos);
    // no dropdown when even the smallest size holds every row (none would split)
    if (sizes.length > 1 && nRow > Math.min(...sizes.filter(n => n > 0))) {
      const sel = elem(doc, "select", { "aria-label": "Rows per page" }, bar);
      // 0: every row on one page (∞)
      sizes.forEach(n => elem(doc, "option", { value: n, textContent: n || "∞" }, sel));
      sel.onchange = () => { state.pageSize = +sel.value; state.page = 0; repage(); };
    }
    return total => {
      // a page size of 0 is one page holding everything
      const n = state.pageSize || total || 1,
            last = Math.max(0, Math.ceil(total / n) - 1),
            // under a filter, append the full count in parens (a symbol, no i18n)
            all = total < nRow ? ` (${nRow})` : "";
      pos.textContent = (total ?
        `${state.page * n + 1}–${Math.min(total, (state.page + 1) * n)} / ${total}` :
        "0 / 0") + all;
      btns.forEach((b, i) => b.disabled = i < 2 ? !state.page : state.page === last);
    };
  }

  // Enhance a mounted table that opted in (idempotent via the dataset flag).
  const onMount = (el, spec) => {
    if (!spec?.interactive || el.dataset.ltiOn) return;
    el.dataset.ltiOn = "1";
    enhance(el, spec);
  };

  LT.plugins.interactive = { matcher, computeView, pageSlice, enhance };
  LT.onMount.push(onMount);
  // Core drains its render queue before this file loads, so the callback above
  // only sees later renders; enhance the tables already on the page now.
  // (Skipped in non-DOM hosts, e.g. the Node.js tests.)
  if (typeof document !== "undefined")
    $$(document, ".lt-table").forEach(el => onMount(el, el._ltSpec));
})(typeof window !== "undefined" ? window : globalThis);
