/* lt-interactive.js — opt-in interactivity for lt tables (search, sort, column
 * filters, pagination, column resizing).
 *
 * A plugin on the existing LT global (see lt.js): it adds no new global. For a
 * table whose spec carries `interactive`, it adds the requested controls and
 * re-renders <tbody> through the core `spec._viewRows` seam. Every control is a
 * row of the table itself — the search box in <thead>, the pager in <tfoot> —
 * so it is exactly as wide as the table and scrolls with it. Flat rows only (no
 * row groups or indentation); such tables stay static, with a console warning.
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

  // --- Small DOM helpers, so building the controls stays terse ---
  const $ = (el, sel) => el.querySelector(sel),
        $$ = (el, sel) => el.querySelectorAll(sel),
        on = (t, type, fn, opts) => t.addEventListener(type, fn, opts),
        off = (t, type, fn) => t.removeEventListener(type, fn);
  // Create a <tag> and assign `props`: a dashed key ("aria-label") sets an
  // attribute, any other key ("className", "type", "textContent") a DOM
  // property. Appends to `parent` when given, and returns the new element.
  function elem(doc, tag, props = {}, parent) {
    const e = doc.createElement(tag);
    for (const k in props)
      k.includes("-") ? e.setAttribute(k, props[k]) : (e[k] = props[k]);
    return parent ? parent.appendChild(e) : e;
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

  // The view pipeline (pure — no DOM): per-column filters, then the table-wide
  // search, then sort, yielding the 1-based original row indices for
  // `spec._viewRows`. `disp[col][i]` is a cell's displayed text (what substring
  // search matches); `state` holds the filter terms (`filters[col]`), the
  // search term, and the sort keys (`sort`, an array of `{col, dir}` applied in
  // order). Filters and the search are combined with AND: a row must pass all
  // of them.
  function computeView(spec, disp, state) {
    const cols = spec._cols || [], data = spec.data || {},
          cell = (c, r) => ({
            raw: data[c]?.[r - 1] ?? null, disp: disp[c]?.[r - 1] ?? ""
          });
    let idx = Array.from({ length: (data[cols[0]] || []).length }, (_, i) => i + 1);

    // filters first: each looks at one cell, so they are the cheapest
    for (const c in state.filters || {}) {
      const pred = matcher(state.filters[c]);
      if (pred) idx = idx.filter(r => pred([cell(c, r)]));
    }
    const pred = matcher(state.term);
    if (pred) idx = idx.filter(r => pred(cols.map(c => cell(c, r))));

    // sort by each key in turn, falling through to the next on a tie; a key's
    // column (resolved once) carries its numeric test and direction. nulls sort
    // last regardless of direction, so the direction never applies to them.
    const keys = (state.sort || []).map(k => {
      const col = data[k.col];
      return col && { col, num: numCol(col), dir: k.dir === "desc" ? -1 : 1 };
    }).filter(Boolean);
    if (keys.length) {
      coll ||= new Intl.Collator();
      idx.sort((a, b) => {
        for (const { col, num, dir } of keys) {
          const x = col[a - 1], y = col[b - 1], xn = x == null, yn = y == null;
          if (xn || yn) { if (xn !== yn) return xn ? 1 : -1; continue; }
          const c = num ? x - y : coll.compare(String(x), String(y));
          if (c) return dir * c;
        }
        return 0;
      });
    }
    return idx;
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

  // Enhanceable only when the rows are flat: row groups and indentation give the
  // row order a meaning of its own (grouping, hierarchy) that reordering or
  // dropping rows would destroy. Column spanners, explicit or from `auto_span`,
  // are no obstacle: they are <thead> rows, and only <tbody> is ever re-rendered.
  // Row-keyed styles and footnotes are fine too — core keys them to the original
  // row indices, which is what the view carries.
  const isFlat = spec => !spec.row_group &&
    !(spec.ops || []).some(o => o.type === "row_group" || o.type === "indent");

  // Displayed text per column, keyed to the original row order. It does not
  // change with the view, so capture it once from the initial full render.
  function captureDisplay(el, cols) {
    const disp = {};
    cols.forEach(c => disp[c] = []);
    $$(el, "tbody tr").forEach((tr, ri) => cols.forEach(
      (c, ci) => disp[c][ri] = tr.children[ci]?.textContent ?? ""
    ));
    return disp;
  }

  function enhance(el, spec) {
    if (!isFlat(spec)) return console.warn(
      "lt: interactive tables need flat rows (no row groups or indentation); " +
      "rendering a static table."
    );
    const opts = spec.interactive, cols = spec._cols || [],
          disp = captureDisplay(el, cols),
          // the bottom header row: the one whose cells line up with `cols`
          hrow = [...$$(el, "thead tr")].pop(),
          // an array `sort` on the options is an initial sort (a list of key
          // strings or objects, see parseKey); `true` just turns sorting on
          state = {
            filters: {}, page: 0, pageSize: 0,
            sort: Array.isArray(opts.sort) ? opts.sort.map(parseKey) : []
          };
    let view,          // filtered + sorted indices, cached across page turns
        sync = () => {};  // pager readout, replaced by addPaginate()

    // `stale` means the view itself changed (a term or the sort), as opposed to
    // only the page: recompute it and go back to the first page.
    const refresh = (stale = true) => {
      if (stale) { view = computeView(spec, disp, state); state.page = 0; }
      const rows = pageSlice(view, state),
            tmp = elem(el.ownerDocument, "template", {
              innerHTML: LT.buildHtml({ ...spec, _viewRows: rows })
            });
      const body = $(tmp.content, "tbody");
      if (!rows.length)  // no matches: a neutral symbol spanning all columns
        body.innerHTML = `<tr class="lti-empty"><td colspan="${cols.length}">—</td></tr>`;
      $(el, "tbody").replaceWith(body);
      sync(view.length);
    };

    if (opts.search !== false) addSearch(el, cols, state, refresh);
    // wire sort before adding the filter row, so it sees the header row only
    if (opts.sort !== false) addSort(hrow, cols, state, refresh);
    if (opts.filter) addFilter(hrow, cols, opts.filter, state, refresh);
    if (opts.resize) addResize(el, hrow, cols.length);
    // `pager` is the page sizes to offer, the first one being the initial
    if (opts.pager) {
      const sizes = Array.isArray(opts.pager) ? opts.pager : [10, 25, 50, 100];
      sync = addPaginate(el, cols, sizes, state, () => refresh(false));
      refresh();  // cut the full render down to the first page
    } else if (state.sort.length) {
      refresh();  // core rendered the rows in file order; apply the initial sort
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

  // Table-wide search box, as the first row of <thead>.
  function addSearch(el, cols, state, refresh) {
    const cell = fullRow(el.tHead || el.createTHead(), "lti-head", cols.length, 0),
          input = cell.appendChild(searchInput(el.ownerDocument, "Search"));
    onType(input, v => { state.term = v; refresh(); });
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
      marks[col] = { th, ind: elem(doc, "span", { className: "lti-sort" }, th) };
      th.onclick = e => { cycle(state, col, e.shiftKey); paint(); refresh(); };
    });
    paint();  // reflect any initial sort carried on the spec
  }

  // A row of per-column search boxes below the headers, inside <thead> so the
  // <tbody> swap leaves it (and what has been typed into it) alone.
  // `opt.columns`, when an array, restricts which columns get a box.
  function addFilter(hrow, cols, opt, state, refresh) {
    const doc = hrow.ownerDocument, only = opt.columns,
          row = elem(doc, "tr", { className: "lti-filters" });
    cols.forEach(c => {
      const cell = elem(doc, "td", {}, row);
      if (Array.isArray(only) && !only.includes(c)) return;
      const input = cell.appendChild(searchInput(doc, `Filter ${c}`));
      onType(input, v => { state.filters[c] = v; refresh(); });
    });
    hrow.parentNode.appendChild(row);
  }

  // The table's <colgroup>, created (one <col> per column) when core emitted
  // none — it only does so for a table given explicit widths on the R side.
  function colGroup(el, nCol) {
    let g = $(el, "colgroup");
    if (!g) {
      const doc = el.ownerDocument;
      g = elem(doc, "colgroup");
      for (let i = 0; i < nCol; i++) elem(doc, "col", {}, g);
      // <colgroup> comes after <caption> (the title), before <thead>
      el.insertBefore(g, el.caption?.nextSibling || el.firstChild);
    }
    return [...g.children];
  }

  // Drag-to-resize column edges: a grip on the right edge of each header cell.
  // The widths live on the <colgroup>, which is outside <tbody> and so survives
  // every re-render. On the first drag the table is switched to fixed layout
  // with every column frozen at the width it has then, so that dragging one
  // edge moves that edge alone instead of reflowing the whole table. A
  // double-click on a grip fits its column to its content.
  function addResize(el, hrow, nCol) {
    const doc = el.ownerDocument, ths = [...$$(hrow, "th")],
          cs = colGroup(el, nCol), wOf = e => e.getBoundingClientRect().width;
    const freeze = () => {
      if (el.classList.contains("lti-fixed")) return;
      const w = ths.map(wOf);
      el.style.width = wOf(el) + "px";
      cs.forEach((c, i) => c.style.width = w[i] + "px");
      el.classList.add("lti-fixed");
    };
    // What column `i` is wide when nothing constrains it: its content width.
    // Measuring it means laying the table out unconstrained and putting the
    // widths back, so only do this on demand (a double-click).
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
    // Give column `i` a width of `w` px, widening or narrowing the table by as
    // much: the other columns keep the widths they have (the wrapper scrolls).
    const setWidth = (i, w) => {
      const old = parseFloat(cs[i].style.width);
      cs[i].style.width = Math.max(w, MIN_COL) + "px";
      el.style.width =
        parseFloat(el.style.width) + parseFloat(cs[i].style.width) - old + "px";
    };
    ths.forEach((th, i) => {
      const grip = elem(doc, "div", { className: "lti-resizer" }, th);
      // the grip sits in a header cell that may sort on click: its own events
      // stop here, or a drag would sort the column as well
      grip.onclick = e => e.stopPropagation();
      grip.ondblclick = e => {
        e.stopPropagation();
        freeze();
        setWidth(i, natural(i));
      };
      grip.onpointerdown = e => {
        e.preventDefault();  // no text selection while dragging
        e.stopPropagation();
        freeze();
        const x0 = e.clientX, w0 = parseFloat(cs[i].style.width),
              move = ev => setWidth(i, w0 + ev.clientX - x0);
        el.classList.add("lti-resizing");
        on(doc, "pointermove", move);
        on(doc, "pointerup", () => {
          off(doc, "pointermove", move);
          el.classList.remove("lti-resizing");
        }, { once: true });
      };
    });
  }

  // Pager as the last row of <tfoot> (after any footnotes), with a page-size
  // <select> when there is more than one size to offer. Both are symbols or
  // numbers only: « ‹ › » for first/previous/next/last and `from–to / total`
  // for the position. Returns the callback that updates them for a new row
  // count.
  function addPaginate(el, cols, sizes, state, repage) {
    const doc = el.ownerDocument;
    let foot = el.tFoot;
    // reuse the core footer if there is one, so the pager is sized like it
    if (!foot) (foot = el.createTFoot()).className = "lt-footer";
    const bar = elem(doc, "div", { className: "lti-pager" },
            fullRow(foot, "lti-pager-row", cols.length, -1)),
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
    if (sizes.length > 1) {
      const sel = elem(doc, "select", { "aria-label": "Rows per page" }, bar);
      // 0: every row on one page (∞)
      sizes.forEach(n => elem(doc, "option", { value: n, textContent: n || "∞" }, sel));
      sel.onchange = () => { state.pageSize = +sel.value; state.page = 0; repage(); };
    }
    return total => {
      // a page size of 0 is one page holding everything
      const n = state.pageSize || total || 1,
            last = Math.max(0, Math.ceil(total / n) - 1);
      pos.textContent = total ?
        `${state.page * n + 1}–${Math.min(total, (state.page + 1) * n)} / ${total}` :
        "0 / 0";
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
