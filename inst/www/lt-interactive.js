/* lt-interactive.js — opt-in interactivity for lt tables (search, sort, column
 * filters, pagination).
 *
 * A plugin on the existing LT global (see lt.js): it adds no new global. For a
 * table whose spec carries `interactive`, it adds the requested controls and
 * re-renders <tbody> through the core `spec._viewRows` seam. Every control is a
 * row of the table itself — the search box in <thead>, the pager in <tfoot> —
 * so it is exactly as wide as the table and scrolls with it. Flat tables only
 * (no row groups / spanners / rowspan); others stay static, with a console
 * warning.
 */
(root => {
  "use strict";
  const LT = root.LT;
  // Bail out if core is absent or too old, or the plugin already loaded.
  if (!LT?.onMount || LT.plugins.interactive) return;

  let coll;  // locale-aware comparator, built on first use and reused
  // A column is numeric if its first non-null value is a number (how core
  // lt.js decides alignment and formatting).
  const numCol = col => typeof col.find(v => v != null) === "number";

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
  // search term, and the sorted column/direction. Filters and the search are
  // combined with AND: a row must pass all of them.
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

    const col = data[state.sortCol];
    if (col && state.sortDir) {
      const num = numCol(col), dir = state.sortDir === "desc" ? -1 : 1;
      coll ||= new Intl.Collator();
      idx.sort((a, b) => {
        const x = col[a - 1], y = col[b - 1];
        // nulls sort last in both directions
        if (x == null || y == null) return x == y ? 0 : x == null ? 1 : -1;
        return dir * (num ? x - y : coll.compare(String(x), String(y)));
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

  // Enhanceable only when the table is flat: no row groups, spanners, rowspan,
  // or row-indexed ops (those make row order and row indices interdependent).
  const isFlat = spec => !spec.row_group && !spec.auto_span &&
    !spec.spanners?.length &&
    !(spec.ops || []).some(o => o.type === "row_group" || o.rows?.length);

  // Displayed text per column, keyed to the original row order. It does not
  // change with the view, so capture it once from the initial full render.
  function captureDisplay(el, cols) {
    const disp = {};
    cols.forEach(c => disp[c] = []);
    el.querySelectorAll("tbody tr").forEach((tr, ri) => cols.forEach(
      (c, ci) => disp[c][ri] = tr.children[ci]?.textContent ?? ""
    ));
    return disp;
  }

  function enhance(el, spec) {
    if (!isFlat(spec)) return console.warn(
      "lt: interactive tables must be flat (no row groups, spanners, or " +
      "rowspan); rendering a static table."
    );
    const opts = spec.interactive, cols = spec._cols || [],
          disp = captureDisplay(el, cols),
          // the bottom header row: the one whose cells line up with `cols`
          hrow = [...el.querySelectorAll("thead tr")].pop(),
          state = { filters: {}, page: 0, pageSize: 0 };
    let view,          // filtered + sorted indices, cached across page turns
        sync = () => {};  // pager readout, replaced by addPaginate()

    // `stale` means the view itself changed (a term or the sort), as opposed to
    // only the page: recompute it and go back to the first page.
    const refresh = (stale = true) => {
      if (stale) { view = computeView(spec, disp, state); state.page = 0; }
      const rows = pageSlice(view, state),
            tmp = el.ownerDocument.createElement("template");
      tmp.innerHTML = LT.buildHtml({ ...spec, _viewRows: rows });
      const body = tmp.content.querySelector("tbody");
      if (!rows.length)  // no matches: a neutral symbol spanning all columns
        body.innerHTML = `<tr class="lti-empty"><td colspan="${cols.length}">—</td></tr>`;
      el.querySelector("tbody").replaceWith(body);
      sync(view.length);
    };

    if (opts.search !== false) addSearch(el, cols, state, refresh);
    // wire sort before adding the filter row, so it sees the header row only
    if (opts.sort !== false) addSort(hrow, cols, state, refresh);
    if (opts.filter) addFilter(hrow, cols, opts.filter, state, refresh);
    // `paginate` is the page sizes to offer, the first one being the initial
    if (opts.paginate) {
      const sizes = Array.isArray(opts.paginate) ? opts.paginate : [10, 25, 50, 100];
      sync = addPaginate(el, cols, sizes, state, () => refresh(false));
      refresh();  // cut the full render down to the first page
    }
  }

  // A search input: `type="search"` lets the browser supply the affordance (and
  // a clear button), so there is no icon or placeholder text to translate; the
  // label is for screen readers only.
  function searchInput(doc, label) {
    const input = doc.createElement("input");
    input.type = "search";
    input.setAttribute("aria-label", label);
    return input;
  }

  // A full-width row of the table, for a control that belongs to the table as a
  // whole. Living inside the table (instead of beside it) is what keeps the
  // controls exactly as wide as the table, however narrow that is, and keeps
  // everything inside the core `.lt-wrap` scroll box. Returns its single cell.
  function fullRow(sect, cls, nCol, pos) {
    const cell = sect.insertRow(pos).appendChild(
      sect.ownerDocument.createElement("td")
    );
    cell.parentNode.className = cls;
    cell.colSpan = nCol;
    return cell;
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
    input.className = "lti-search";
    onType(input, v => { state.term = v; refresh(); });
  }

  // Click-to-sort headers, one column at a time: clicking cycles asc → desc →
  // unsorted. The indicator and aria-sort live on the <th>, which survives the
  // <tbody> swap, so they need no re-render.
  function addSort(hrow, cols, state, refresh) {
    const doc = hrow.ownerDocument, marks = [];
    hrow.querySelectorAll("th").forEach((th, ci) => {
      const col = cols[ci];
      if (col == null) return;
      th.classList.add("lti-sortable");
      const ind = th.appendChild(doc.createElement("span"));
      ind.className = "lti-sort";
      marks.push([th, ind]);
      th.onclick = () => {
        const dir = state.sortCol !== col ? "asc" : state.sortDir === "asc" ?
          "desc" : state.sortDir === "desc" ? null : "asc";
        state.sortCol = col;
        state.sortDir = dir;
        marks.forEach(([t, m]) => {
          t.removeAttribute("aria-sort");
          m.textContent = "";
        });
        if (dir) {
          th.setAttribute("aria-sort", dir === "asc" ? "ascending" : "descending");
          ind.textContent = dir === "asc" ? "▲" : "▼";
        }
        refresh();
      };
    });
  }

  // A row of per-column search boxes below the headers, inside <thead> so the
  // <tbody> swap leaves it (and what has been typed into it) alone.
  // `opt.columns`, when an array, restricts which columns get a box.
  function addFilter(hrow, cols, opt, state, refresh) {
    const doc = hrow.ownerDocument, only = opt.columns,
          row = doc.createElement("tr");
    row.className = "lti-filters";
    cols.forEach(c => {
      const cell = row.appendChild(doc.createElement("td"));
      if (Array.isArray(only) && !only.includes(c)) return;
      const input = cell.appendChild(searchInput(doc, `Filter ${c}`));
      onType(input, v => { state.filters[c] = v; refresh(); });
    });
    hrow.parentNode.appendChild(row);
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
    const bar = fullRow(foot, "lti-pager-row", cols.length, -1)
            .appendChild(doc.createElement("div")),
          pos = doc.createElement("span");
    state.pageSize = sizes[0];
    bar.className = "lti-pager";
    pos.className = "lti-pos";
    // the last page is clamped by pageSlice(), so a large number will do
    const steps = [() => 0, p => p - 1, p => p + 1, () => 1e9];
    const btns = ["«", "‹", "›", "»"].map((glyph, i) => {
      const b = bar.appendChild(doc.createElement("button"));
      b.type = "button";
      b.textContent = glyph;
      b.setAttribute("aria-label", ["First", "Previous", "Next", "Last"][i]);
      b.onclick = () => { state.page = steps[i](state.page); repage(); };
      return b;
    });
    bar.appendChild(pos);
    if (sizes.length > 1) {
      const sel = bar.appendChild(doc.createElement("select"));
      sel.setAttribute("aria-label", "Rows per page");
      sizes.forEach(n => {
        const o = sel.appendChild(doc.createElement("option"));
        o.value = n;
        o.textContent = n || "∞";  // 0: every row
      });
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
    document.querySelectorAll(".lt-table").forEach(el => onMount(el, el._ltSpec));
})(typeof window !== "undefined" ? window : globalThis);
