/* lt-interactive.js — opt-in interactivity for lt tables (search + sort).
 *
 * A plugin on the existing LT global (see lt.js): it adds no new global. For a
 * table whose spec carries `interactive`, it adds a search box and
 * click-to-sort headers, re-rendering <tbody> through the core `spec._viewRows`
 * seam. Flat tables only (no row groups / spanners / rowspan); others stay
 * static, with a console warning.
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

  // The view pipeline (pure — no DOM): search, then sort, yielding the 1-based
  // original row indices for `spec._viewRows`. `disp[col][i]` is a cell's
  // displayed text (what substring search matches); `state` holds the term and
  // the sorted column/direction.
  function computeView(spec, disp, state) {
    const cols = spec._cols || [], data = spec.data || {};
    let idx = Array.from({ length: (data[cols[0]] || []).length }, (_, i) => i + 1);

    const pred = matcher(state.term);
    if (pred) idx = idx.filter(r => pred(cols.map(c => ({
      raw: data[c]?.[r - 1] ?? null, disp: disp[c]?.[r - 1] ?? ""
    }))));

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
          disp = captureDisplay(el, cols), state = {};

    const refresh = () => {
      const view = computeView(spec, disp, state),
            tmp = el.ownerDocument.createElement("template");
      tmp.innerHTML = LT.buildHtml({ ...spec, _viewRows: view });
      const body = tmp.content.querySelector("tbody");
      if (!view.length)  // no matches: a neutral symbol spanning all columns
        body.innerHTML = `<tr class="lti-empty"><td colspan="${cols.length}">—</td></tr>`;
      el.querySelector("tbody").replaceWith(body);
    };

    if (opts.search !== false) addSearch(el, state, refresh);
    if (opts.sort !== false) addSort(el, cols, state, refresh);
  }

  // Table-wide search box above the table. `type="search"` lets the browser
  // supply the affordance (and a clear button), so there is no icon or
  // placeholder text to translate; the label is for screen readers only.
  function addSearch(el, state, refresh) {
    const wrap = el.closest(".lt-wrap") || el,
          input = el.ownerDocument.createElement("input");
    input.type = "search";
    input.className = "lti-search";
    input.setAttribute("aria-label", "Search");
    const apply = () => { state.term = input.value; refresh(); };
    let timer;
    // Debounce typing; Enter (or leaving the box) applies at once.
    input.oninput = () => { clearTimeout(timer); timer = setTimeout(apply, 150); };
    input.onchange = () => { clearTimeout(timer); apply(); };
    wrap.parentNode.insertBefore(input, wrap);
  }

  // Click-to-sort headers, one column at a time: clicking cycles asc → desc →
  // unsorted. The indicator and aria-sort live on the <th>, which survives the
  // <tbody> swap, so they need no re-render.
  function addSort(el, cols, state, refresh) {
    const doc = el.ownerDocument, marks = [];
    el.querySelectorAll("thead tr:last-child th").forEach((th, ci) => {
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

  // Enhance a mounted table that opted in (idempotent via the dataset flag).
  const onMount = (el, spec) => {
    if (!spec?.interactive || el.dataset.ltiOn) return;
    el.dataset.ltiOn = "1";
    enhance(el, spec);
  };

  LT.plugins.interactive = { matcher, computeView, enhance };
  LT.onMount.push(onMount);
  // Core drains its render queue before this file loads, so the callback above
  // only sees later renders; enhance the tables already on the page now.
  // (Skipped in non-DOM hosts, e.g. the Node.js tests.)
  if (typeof document !== "undefined")
    document.querySelectorAll(".lt-table").forEach(el => onMount(el, el._ltSpec));
})(typeof window !== "undefined" ? window : globalThis);
