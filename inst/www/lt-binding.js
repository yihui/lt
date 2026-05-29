// Shiny output binding for lt tables
'use strict';

$(document).ready(() => {
  const seen = new Set();
  const ensureCss = items => {
    if (!items) return;
    for (const it of items) {
      const key = it.href || it.content;
      if (seen.has(key)) continue;
      seen.add(key);
      const el = it.href
        ? Object.assign(document.createElement('link'), { rel: 'stylesheet', href: it.href })
        : Object.assign(document.createElement('style'), { textContent: it.content });
      document.head.appendChild(el);
    }
  };
  const binding = new Shiny.OutputBinding();
  Object.assign(binding, {
    find: scope => $(scope).find('.lt-output'),
    renderValue: (el, data) => {
      if (!data) { el.innerHTML = ''; return; }
      ensureCss(data.spec && data.spec.css);
      el.innerHTML = LT.buildHtml(data.spec);
    },
    renderError: (el, err) => { console.error('lt:', err.message); }
  });
  Shiny.outputBindings.register(binding, 'lt');
});
