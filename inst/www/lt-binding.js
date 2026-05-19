// Shiny output binding for lt tables
'use strict';

$(document).ready(() => {
  const binding = new Shiny.OutputBinding();
  Object.assign(binding, {
    find: scope => $(scope).find('.lt-output'),
    renderValue: (el, data) => {
      if (!data) { el.innerHTML = ''; return; }
      el.innerHTML = LT.buildHtml(data.spec);
    },
    renderError: (el, err) => { console.error('lt:', err.message); }
  });
  Shiny.outputBindings.register(binding, 'lt');
});
