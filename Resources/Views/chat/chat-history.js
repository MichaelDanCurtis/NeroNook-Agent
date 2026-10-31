/* Filter already-loaded conversation titles; no provider, SDK or storage access. */
(function () {
  'use strict';
  function titleMatches(title, query) {
    const normalize = value => String(value).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase();
    return normalize(title).includes(normalize(String(query).slice(0, 256).trim()));
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = { titleMatches };
  if (typeof document === 'undefined') return;
  const byID = id => document.getElementById(id);
  const list = byID('conversations'), input = byID('historyQuery'), drawer = byID('history');
  if (!list || !input || !drawer) return;
  const historyButton = byID('historyButton'), toggleHistory = historyButton.onclick;
  if (typeof toggleHistory === 'function') historyButton.onclick = event => {
    if (byID('chatFind')?.hidden === false) byID('chatFindClose').onclick();
    toggleHistory(event);
    if (!drawer.hidden) { input.focus(); input.select(); }
  };
  function filter() {
    const buttons = Array.from(list.children).filter(node => node.tagName === 'BUTTON');
    let count = 0;
    buttons.forEach(button => { button.hidden = !titleMatches(button.textContent, input.value); if (!button.hidden) count++; });
    const query = input.value.trim();
    byID('historyClear').hidden = !query;
    byID('historyResult').textContent = !buttons.length ? 'No saved conversations yet.' : !count ? 'No conversations match. Try another title.' : query ? `${count} of ${buttons.length} conversations` : `${buttons.length} conversations`;
  }
  input.addEventListener('input', filter);
  byID('historyClear').onclick = () => { input.value = ''; filter(); input.focus(); };
  // Observe loaded titles only. Filtering changes hidden attributes, not these records.
  new MutationObserver(filter).observe(list, { childList: true, characterData: true, subtree: true });
  document.addEventListener('keydown', event => {
    if (!event.isComposing && !event.defaultPrevented && event.key === 'Escape' && !drawer.hidden && byID('chatFind')?.hidden !== false) {
      event.preventDefault(); drawer.hidden = true; byID('historyButton').focus();
    }
  });
  filter();
})();
