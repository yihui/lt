/* lt-input.js — editable cells and a Shiny input binding for lt tables.
 *
 * Plugin on the LT global (see lt.js). For a spec with `input` (names of
 * editable columns), makes those body cells contenteditable and writes edits
 * back into spec.data. Not for rowspan row groups or lt_interactive(), which
 * reorder rows. The Shiny binding reports spec.data as the input value.
 */
(root => {
  "use strict";
  const LT = root.LT;
  if (!LT?.onMount || LT.plugins.input) return;
  const { $$, on, numCol } = LT;

  const onMount = (tbl, spec) => {
    if (!spec?.input || spec._rowspan || spec.interactive) return;
    const rows = [...$$(tbl.tBodies[0], "tr:not(.lt-row-group)")],
          cols = spec._cols,
          // [column, row index] of an editable cell hit by event `e`
          hit = e => {
            const td = e.target.closest?.("td[contenteditable]");
            return td && [td, cols[td.cellIndex], rows.indexOf(td.parentNode)];
          };
    tbl.classList.add("lt-edit");
    rows.forEach(tr => cols.forEach((c, i) => {
      if (spec.input.includes(c)) tr.cells[i].contentEditable = "plaintext-only";
    }));
    on(tbl, "focusin", e => {  // edit the raw value, not its display
      const [td, c, r] = hit(e) || [];
      if (td) td.textContent = spec.data[c][r] ?? "";
    });
    on(tbl, "focusout", e => {
      const [td, c, r] = hit(e) || [];
      if (!td) return;
      const col = spec.data[c], v = td.textContent.trim();
      if (!numCol(col)) col[r] = td.textContent;
      else if (isNaN(v)) td.textContent = col[r] ?? "";  // reject non-numeric
      else col[r] = v === "" ? null : +v;
      tbl.dispatchEvent(new CustomEvent("lt-edit", { bubbles: true }));
    });
    on(tbl, "keydown", e => {  // Enter commits and moves down a row
      const [td, , r] = hit(e) || [];
      if (!td || e.key !== "Enter") return;
      e.preventDefault();
      (rows[r + 1]?.cells[td.cellIndex] || td).focus();
      td.blur();
    });
  };

  LT.plugins.input = 1;
  LT.onMount.push(onMount);
  if (typeof document !== "undefined")
    $$(document, ".lt-table").forEach(t => onMount(t, t._ltSpec));

  // Shiny input binding: <div class="lt-input" data-spec='{...}'>
  if (!root.Shiny) return;
  const draw = (el, spec) => el._tbl = LT.render(el, spec);
  Shiny.inputBindings.register(Object.assign(new Shiny.InputBinding(), {
    find: scope => $(scope).find(".lt-input"),
    initialize: el => draw(el, JSON.parse(el.dataset.spec)),
    getType: () => "lt.table",
    getValue: el => { const s = el._tbl._ltSpec; return { data: s.data, matrix: s.matrix }; },
    subscribe: (el, cb) => $(el).on("lt-edit.lt", () => cb(true)),
    unsubscribe: el => $(el).off(".lt"),
    receiveMessage: (el, msg) => { draw(el, { input: el._tbl._ltSpec.input, ...msg.spec }); $(el).trigger("lt-edit"); }
  }), "lt.input");
})(typeof window !== "undefined" ? window : globalThis);
