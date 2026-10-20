/* lt-input.js — editable cells and a Shiny input binding for lt tables.
 *
 * Plugin on the LT global (see lt.js). For a spec with `input` (names of
 * editable columns), makes those body cells contenteditable and writes edits
 * back into spec.data. Not for tables with rowspan row groups or
 * lt_interactive(), which reorder rows. The binding (when Shiny is present)
 * reports spec.data as the input value.
 */
(root => {
  "use strict";
  const LT = root.LT;
  if (!LT?.onMount || LT.plugins.input) return;

  const numCol = col => typeof col.find(v => v != null) === "number";

  const onMount = (tbl, spec) => {
    if (!spec?.input || spec._rowspan || spec.interactive || tbl.dataset.ltEdit) return;
    tbl.dataset.ltEdit = "1";
    const rows = [...tbl.tBodies[0].querySelectorAll("tr:not(.lt-row-group)")];
    rows.forEach(tr => spec._cols.forEach((c, i) => {
      if (spec.input.includes(c)) tr.cells[i].contentEditable = "plaintext-only";
    }));
    const loc = td => [spec._cols[td.cellIndex], rows.indexOf(td.parentNode)];
    const at = e => {
      const td = e.target.closest?.("td[contenteditable]");
      return td && tbl.contains(td) ? td : null;
    };
    tbl.addEventListener("focusin", e => {  // edit the raw value, not its display
      const td = at(e); if (!td) return;
      const [c, r] = loc(td);
      td.textContent = spec.data[c][r] ?? "";
    });
    tbl.addEventListener("focusout", e => {
      const td = at(e); if (!td) return;
      const [c, r] = loc(td), col = spec.data[c], v = td.textContent.trim();
      if (!numCol(col)) col[r] = td.textContent;
      else if (v === "") col[r] = null;
      else if (isNaN(v)) td.textContent = col[r] ?? "";  // reject non-numeric
      else col[r] = +v;
      tbl.dispatchEvent(new CustomEvent("lt-edit", { bubbles: true }));
    });
    tbl.addEventListener("keydown", e => {  // Enter commits, moves down a row
      const td = at(e);
      if (!td || e.key !== "Enter") return;
      e.preventDefault();
      rows[rows.indexOf(td.parentNode) + 1]?.cells[td.cellIndex].focus();
      if (!td.matches(":focus")) td.blur();
    });
  };

  LT.plugins.input = { onMount };
  LT.onMount.push(onMount);
  if (typeof document !== "undefined")
    document.querySelectorAll(".lt-table").forEach(t => onMount(t, t._ltSpec));

  // Shiny input binding: <div class="lt-input" data-spec='{...}'>
  if (!root.Shiny) return;
  const b = new Shiny.InputBinding(), draw = (el, spec) => {
    el._tbl = LT.render(el, spec);
  };
  Object.assign(b, {
    find: scope => $(scope).find(".lt-input"),
    initialize: el => draw(el, JSON.parse(el.dataset.spec)),
    getType: () => "lt.table",
    getValue: el => el._tbl._ltSpec.data,
    subscribe: (el, cb) => $(el).on("lt-edit.lt", () => cb(true)),
    unsubscribe: el => $(el).off(".lt"),
    receiveMessage: (el, msg) => {
      draw(el, msg.spec);
      $(el).trigger("lt-edit");
    }
  });
  Shiny.inputBindings.register(b, "lt.input");
})(typeof window !== "undefined" ? window : globalThis);
