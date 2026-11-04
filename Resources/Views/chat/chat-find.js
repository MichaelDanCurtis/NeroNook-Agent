/* Local, rendered-message search. No provider/SDK calls or persisted queries. */
(function () {
  'use strict';
  function matches(texts, query, limit = 500) {
    query = String(query).slice(0, 256).trim();
    const hits = [];
    if (!query) return { hits, overflow: false };
    const pattern = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'giu');
    for (let message = 0; message < texts.length; message++) {
      pattern.lastIndex = 0;
      let found;
      while ((found = pattern.exec(texts[message]))) {
        if (hits.length >= limit) return { hits, overflow: true };
        hits.push({ message, start: found.index, end: found.index + found[0].length });
      }
    }
    return { hits, overflow: false };
  }
  function segments(lengths, start, end) {
    const result = []; let offset = 0;
    lengths.forEach((length, node) => {
      const a = Math.max(start, offset), b = Math.min(end, offset + length);
      if (a < b) result.push({ node, start: a - offset, end: b - offset });
      offset += length;
    });
    return result;
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = { matches, segments };
  if (typeof document === 'undefined') return;
  const byID = id => document.getElementById(id);
  const root = byID('messages'), bar = byID('chatFind'), input = byID('chatFindQuery');
  if (!root || !bar || !input) return;
  let groups = [], active = 0, overflow = false, frame = 0;
  const talking = () => document.body.classList.contains('nc-talking');
  const observer = new MutationObserver(() => {
    if (!bar.hidden && !frame) frame = requestAnimationFrame(() => { frame = 0; redraw(false); });
  });
  const observe = () => observer.observe(root, { childList: true, characterData: true, subtree: true });
  function clearHighlights() {
    const parents = new Set();
    root.querySelectorAll('mark.nc-find-hit').forEach(mark => {
      parents.add(mark.parentNode); mark.replaceWith(document.createTextNode(mark.textContent));
    });
    parents.forEach(parent => parent.normalize());
  }
  function select(jump) {
    groups.forEach((group, index) => group.forEach(mark => mark.classList.toggle('nc-find-current', index === active)));
    const label = talking() ? 'Stop Talk to search' : !input.value.trim() ? 'Loaded messages' : groups.length ? `${active + 1} of ${groups.length}${overflow ? '+' : ''}` : 'No matches';
    if (byID('chatFindCount').textContent !== label) byID('chatFindCount').textContent = label;
    byID('chatFindPrevious').disabled = byID('chatFindNext').disabled = groups.length === 0;
    if (jump && groups[active]?.[0]) groups[active][0].scrollIntoView({ block: 'center', behavior: 'auto' });
  }
  function redraw(jump) {
    observer.disconnect();
    try {
      clearHighlights(); groups = [];
      input.disabled = talking();
      if (input.disabled) { select(false); return; }
      const bodies = Array.from(root.querySelectorAll('.message .body'));
      const nodes = bodies.map(body => {
        const result = [], walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT);
        let node; while ((node = walker.nextNode())) result.push(node);
        return result;
      });
      const found = matches(nodes.map(list => list.map(n => n.data).join('')), input.value);
      overflow = found.overflow;
      const fragments = new Map();
      found.hits.forEach((hit, group) => {
        groups.push([]);
        segments(nodes[hit.message].map(n => n.length), hit.start, hit.end).forEach(part => {
          const node = nodes[hit.message][part.node];
          if (!fragments.has(node)) fragments.set(node, []);
          fragments.get(node).push({ ...part, group });
        });
      });
      fragments.forEach((parts, node) => {
        parts.sort((a, b) => b.start - a.start).forEach(part => {
          const middle = node.splitText(part.start); middle.splitText(part.end - part.start);
          const mark = document.createElement('mark'); mark.className = 'nc-find-hit'; mark.textContent = middle.data;
          middle.replaceWith(mark); groups[part.group].push(mark);
        });
      });
      active = Math.min(active, Math.max(0, groups.length - 1)); select(jump);
    } finally { observe(); }
  }
  function open() {
    byID('history').hidden = true;
    bar.hidden = false; byID('agentMenu').open = false; redraw(false);
    if (input.disabled) byID('chatFindClose').focus(); else { input.focus(); input.select(); }
  }
  function close() {
    if (frame) { cancelAnimationFrame(frame); frame = 0; }
    bar.hidden = true; input.value = ''; observer.disconnect();
    clearHighlights(); groups = []; active = 0; observe();
    if (talking()) byID('talkStop').focus(); else byID('draft').focus();
  }
  function move(delta) { if (groups.length) { active = (active + delta + groups.length) % groups.length; select(true); } }
  byID('findConversation').onclick = open;
  byID('chatFindClose').onclick = close;
  byID('chatFindPrevious').onclick = () => move(-1);
  byID('chatFindNext').onclick = () => move(1);
  input.oninput = () => { active = 0; redraw(true); };
  input.onkeydown = event => { if (!event.isComposing && event.key === 'Enter') { event.preventDefault(); move(event.shiftKey ? -1 : 1); } };
  document.addEventListener('keydown', event => {
    if (event.isComposing) return;
    if ((event.metaKey || event.ctrlKey) && !event.altKey && event.key.toLowerCase() === 'f') {
      event.preventDefault(); event.stopPropagation(); open();
    } else if (!bar.hidden && event.key === 'Escape') {
      event.preventDefault(); event.stopPropagation(); close();
    }
  });
  let priorTalk = talking();
  new MutationObserver(() => {
    const current = talking();
    if (current !== priorTalk) { priorTalk = current; if (!bar.hidden) redraw(false); }
  }).observe(document.body, { attributes: true, attributeFilter: ['class'] });
  observe();
})();
