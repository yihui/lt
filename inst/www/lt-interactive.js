/* lt-interactive.js — opt-in interactivity for lt tables (sort + search).
 *
 * Registers as a plugin on the existing LT global (see lt.js): it adds no new
 * global. When a table's spec carries `interactive`, the plugin adds a
 * table-wide search box and click-to-sort headers, then re-renders <tbody> via
 * the core `spec._viewRows` seam. Interactivity targets flat tables only (no
 * row groups / spanners / rowspan); other tables render static with a warning.
 */
(root => {
  "use strict";
  const LT = root.LT;
  if (!LT || LT.plugins?.interactive) return;  // core absent or already loaded

  const SEARCH_DEBOUNCE = 150;
  // Locale-aware string comparator, built once and reused across all tables.
  let coll;
  const collator = () => coll || (coll = new Intl.Collator());
  // A column is numeric if its first non-null value is a number (matches how
  // core lt.js decides alignment/formatting).
  const numCol = col => col?.length && typeof col.find(v => v != null) === "number";

  // Compile a matcher for a search term, ported from forestly's
  // inst/js/search-filter.js so results stay consistent across the projects.
  // Returns a predicate over a row's searched cells (`{raw, disp}` objects), or
  // null to match every row. Two modes:
  //  - Expression mode (term references the cell variable `x`, e.g. `x > 5`,
  //    `x !== "Rash"`, `!x.includes("itch")`): evaluated against the *raw*
  //    value (as string, and as a finite number when applicable). A leading `!`
  //    or an `!=` is negation — a row is kept only when *every* searched cell
  //    satisfies the test; otherwise *any* cell keeps the row.
  //  - Substring mode otherwise: case-insensitive match against the *display*
  //    text; a leading `!` negates.
  function defaultMatch(term) {
    const v = String(term == null ? "" : term).trim();
    if (v === "") return null;
    if (/(^|[^\w$])x([^\w$]|$)/.test(v)) {
      let fn;
      try { fn = new Function("x", "return (" + v + ");"); } catch (e) { fn = null; }
      if (fn) {
        const isNegation = /^\s*!|!=/.test(v),
              method = isNegation ? "every" : "some",
              evalCell = raw => {
                if (raw == null) return isNegation;
                try {
                  const num = Number(raw);
                  return !!fn(String(raw)) ||
                    (raw !== "" && isFinite(num) && !!fn(num));
                } catch (e) { return false; }
              };
        return cells => cells[method](c => evalCell(c.raw));
      }
    }
    const negate = v.charAt(0) === "!",
          term2 = negate ? v.slice(1).trim() : v;
    if (term2 === "") return null;
    const needle = term2.toLowerCase();
    return cells => {
      const match = cells.some(c =>
        c.disp != null && String(c.disp).toLowerCase().indexOf(needle) > -1);
      return negate ? !match : match;
    };
  }

  // The view pipeline (pure — no DOM): rawRows → search → sort → 1-based index
  // array for `spec._viewRows`. `disp[col]` holds the displayed text per row
  // (used for substring search); `state` is { term, sortCol, sortDir }.
  function computeView(spec, disp, state) {
    const cols = spec._cols || [], data = spec.data || {},
          n = cols.length && data[cols[0]] ? data[cols[0]].length : 0;
    let idx = [];
    for (let i = 1; i <= n; i++) idx.push(i);

    const pred = defaultMatch(state.term || "");
    if (pred) idx = idx.filter(r => pred(cols.map(c => ({
      raw: data[c] ? data[c][r - 1] : null,
      disp: disp[c] ? disp[c][r - 1] : ""
    }))));

    if (state.sortCol != null && state.sortDir) {
      const col = data[state.sortCol] || [], numeric = numCol(col),
            dir = state.sortDir === "desc" ? -1 : 1, cmp = collator();
      idx = idx.slice().sort((a, b) => {
        const va = col[a - 1], vb = col[b - 1];
        if (va == null && vb == null) return 0;
        if (va == null) return 1;         // nulls sort last, both directions
        if (vb == null) return -1;
        const d = numeric ? va - vb : cmp.compare(String(va), String(vb));
        return dir * d;
      });
    }
    return idx;
  }

  // A table is enhanceable only when flat: interactive mode does not support
  // row groups, spanners, rowspan, or row-indexed ops in v1.
  function isFlat(spec) {
    if (spec.row_group || spec.auto_span) return false;
    if (spec.spanners && spec.spanners.length) return false;
    for (const op of (spec.ops || []))
      if (op.type === "row_group" || (op.rows && op.rows.length)) return false;
    return true;
  }

  // Capture the displayed text per (column, row) from the initial full render,
  // keyed to original row order. Display text does not change with the view, so
  // this is captured once and reused across sort/search re-renders.
  function captureDisplay(el, cols) {
    const disp = {};
    cols.forEach(c => disp[c] = []);
    el.querySelectorAll("tbody tr").forEach((tr, ri) => {
      cols.forEach((c, ci) => {
        const td = tr.children[ci];
        disp[c][ri] = td ? td.textContent : "";
      });
    });
    return disp;
  }

  function enhance(el, spec) {
    const opts = spec.interactive || {};
    if (!isFlat(spec)) {
      console.warn("lt: interactive mode supports flat tables only " +
        "(no row groups, spanners, or rowspan); rendering a static table.");
      return;
    }
    const cols = spec._cols || [], nCol = cols.length,
          disp = captureDisplay(el, cols),
          state = { term: "", sortCol: null, sortDir: null };

    const refresh = () => {
      const view = computeView(spec, disp, state),
            tmp = el.ownerDocument.createElement("template");
      tmp.innerHTML = LT.buildHtml(Object.assign({}, spec, { _viewRows: view }));
      const body = tmp.content.querySelector("tbody");
      if (!view.length)  // empty result: a neutral symbol spanning all columns
        body.innerHTML = `<tr class="lti-empty"><td colspan="${nCol}">—</td></tr>`;
      el.querySelector("tbody").replaceWith(body);
    };

    if (opts.search !== false) addSearch(el, state, refresh);
    if (opts.sort !== false) addSort(el, cols, state, refresh);
  }

  // Table-wide search: a magnifier glyph + input above the table. No visible
  // words (the glyph is locale-independent); the aria-label is a fixed English
  // token for screen readers, which is accessibility, not translatable UI.
  function addSearch(el, state, refresh) {
    const doc = el.ownerDocument, wrap = el.closest(".lt-wrap") || el,
          bar = doc.createElement("div"), box = doc.createElement("label"),
          input = doc.createElement("input");
    bar.className = "lti-toolbar";
    box.className = "lti-search";
    box.append("🔍");  // 🔍
    input.type = "search";
    input.setAttribute("aria-label", "Search");
    let timer;
    input.oninput = () => {
      clearTimeout(timer);
      timer = setTimeout(() => { state.term = input.value; refresh(); },
        SEARCH_DEBOUNCE);
    };
    box.append(input);
    bar.append(box);
    wrap.parentNode.insertBefore(bar, wrap);
  }

  // Click-to-sort headers. v1 sorts one column at a time: clicking cycles
  // asc → desc → unsorted. The indicator (▲/▼) and aria-sort live on the <th>,
  // which survives the <tbody> swap, so they need no re-render.
  function addSort(el, cols, state, refresh) {
    const ths = el.querySelectorAll("thead tr:last-child th");
    ths.forEach((th, ci) => {
      const col = cols[ci];
      if (col == null) return;
      th.classList.add("lti-sortable");
      const ind = th.ownerDocument.createElement("span");
      ind.className = "lti-sort";
      th.append(ind);
      th.onclick = () => {
        const dir = state.sortCol === col ?
          (state.sortDir === "asc" ? "desc" : state.sortDir === "desc" ? null : "asc") :
          "asc";
        state.sortCol = dir ? col : null;
        state.sortDir = dir;
        ths.forEach(t => {
          t.removeAttribute("aria-sort");
          t.querySelector(".lti-sort").textContent = "";
        });
        if (dir) {
          th.setAttribute("aria-sort", dir === "asc" ? "ascending" : "descending");
          ind.textContent = dir === "asc" ? "▲" : "▼";  // ▲ / ▼
        }
        refresh();
      };
    });
  }

  // Enhance a mounted table if its spec opts in and it has not been enhanced.
  const maybeEnhance = (el, spec) => {
    if (!spec || !spec.interactive || el.dataset.ltiOn) return;
    el.dataset.ltiOn = "1";
    enhance(el, spec);
  };

  LT.plugins.interactive = { defaultMatch, computeView, enhance };
  LT.hooks.add("mounted", ({ el, spec }) => maybeEnhance(el, spec));
  // Core drains its render queue before this file loads, so the 'mounted' hook
  // above misses already-rendered tables. Enhance any interactive ones now
  // (idempotent via the ltiOn guard). Guarded for non-DOM hosts (Node tests).
  if (typeof document !== "undefined")
    document.querySelectorAll(".lt-table").forEach(el => maybeEnhance(el, el._ltSpec));
})(typeof window !== "undefined" ? window : globalThis);
