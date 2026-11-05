/* lt-server.js — server mode for lt-interactive.js: rows stay on a server, and
 * each view (sort, filters, search, page) is fetched from a URL that returns JSON.
 *
 * Must load before lt-interactive.js. `spec.interactive.server` = `{url, n, times,
 * cols}`: the endpoint, total rows, date-time columns (sent as ISO strings),
 * and a sketch per column (see `summary` in lt-interactive.js) for profiles and
 * filter widgets. Request: `url?f=<filters>&s=<keys>&t=<search>&c=<cols>&p=<page>&n=<size>`:
 * `f` is `column<TAB>term` lines (ANDed), `s` sort keys `a:<col>` / `d:<col>`,
 * `t` the free-text search over the visible columns `c`, newline-separated;
 * `n=0` is every row. Response: `{n, page, rows, data, prof?}`: rows in the
 * view, the (clamped) page, the page's data by column, and, when filters keep
 * only some rows, bar counts by column for profiles.
 */
(root => {
  "use strict";
  const LT = root.LT;
  if (!LT?.plugins || LT.plugins.server) return;

  LT.plugins.server = (o, spec) => {
    let seq = 0;
    const enc = encodeURIComponent, sums = o.cols || {};
    // `all`: every row of the view (for download); resolves to the response
    const load = async (state, all) => {
      const q = [["t", state.term || ""], ["p", all ? 0 : state.page || 0], ["n", all ? 0 : state.pageSize || 0]];
      // column conditions (boxes, widgets, and those read from the search box):
      // lines of `column<TAB>term`
      q.push(["f", [state.filters, state.nl].flatMap(f => Object.entries(f || {}).flatMap(
        ([c, ts]) => [].concat(ts).map(t => `${c}\t${t}`))).join("\n")]);
      q.push(["s", (state.sort || []).map(k => `${k.dir === "desc" ? "d" : "a"}:${k.col}`).join("\n")],
        ["c", (spec._cols || []).join("\n")]);
      const id = ++seq, res = await fetch(`${o.url}?${q.map(([k, v]) => `${enc(k)}=${enc(v)}`).join("&")}`);
      if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
      const r = await res.json();
      if (!all && id !== seq) return;  // a newer request superseded this one
      for (const c of o.times || []) r.data[c] &&= r.data[c].map(v => v && new Date(v));
      return r;
    };
    return { load, sum: c => ({ vals: [], ...sums[c] }) };
  };
})(typeof window !== "undefined" ? window : globalThis);
