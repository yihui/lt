/* lt-server.js — server mode for lt-interactive.js: rows stay on a server, and
 * each view (sort, filters, search, page) is fetched from `interactive.data_url`.
 * Must load before lt-interactive.js. The protocol is documented in ?lt_serve.
 *
 * Request: GET `data_url?q=<JSON>`, with JSON
 *   { where?: tree, sort?: [{col, dir: "asc" | "desc"}], page, size, cols }
 * `where` is a leaf `{col, term}` (`col` null: any of `cols`, the visible
 * columns) or `{op: "and" | "or", items}`; `size` 0 is every row.
 * Response: JSON `{n, page, data, prof?}`: rows in the view, the (clamped)
 * page, the page's values by column, and bar counts by column for profiles.
 * Optional `interactive.data_cols` (a summary per column) feed profiles and
 * filter widgets; `data_times` lists date-time columns sent as ISO strings.
 */
(root => {
  "use strict";
  const LT = root.LT;
  if (!LT?.plugins || LT.plugins.server) return;

  LT.plugins.server = (o, spec) => {
    let seq = 0;
    // `all`: every row of the view (for download); resolves to the response
    const load = async (state, all) => {
      // widget terms (a string per column) and boxes (trees) are ANDed
      const items = [...Object.entries(state.filters || {}).map(([col, f]) => typeof f === "string" ? { col, term: f } : f),
        state.where, state.term && { col: null, term: state.term }].filter(Boolean),
        q = {
          where: items.length ? { op: "and", items } : null,
          sort: (state.sort || []).map(k => ({ col: k.col, dir: k.dir === "desc" ? "desc" : "asc" })),
          page: all ? 0 : state.page || 0, size: all ? 0 : state.pageSize || 0, cols: spec._cols || []
        },
        id = ++seq, res = await fetch(`${o.data_url}?q=${encodeURIComponent(JSON.stringify(q))}`);
      if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
      const r = await res.json();
      if (!all && id !== seq) return;  // a newer request superseded this one
      for (const c of o.data_times || []) r.data[c] &&= r.data[c].map(v => v && new Date(v));
      return r;
    };
    // without a summary, a column gets a plain filter box and no profile
    return { load, sum: c => ({ some: true, kind: "mix", m: 0, bins: [], vals: [], ...o.data_cols?.[c] }) };
  };
})(typeof window !== "undefined" ? window : globalThis);
