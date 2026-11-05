// Locked: DOM helpers shared by the popup and the blocked page.

import { allowedLinks } from './format.js';

/** Asks the background for {status, connected, active, now, state}. Never rejects. */
export async function fetchState() {
  try {
    const resp = await chrome.runtime.sendMessage({ type: 'getState' });
    if (resp && typeof resp === 'object') return { ...resp, receivedAt: Date.now() };
  } catch (e) {
    console.warn('[Locked] getState failed', e);
  }
  return { status: 'disconnected', connected: false, active: false, now: Date.now(), state: { active: false }, receivedAt: Date.now() };
}

/** Milliseconds left, corrected for any clock difference between worker and page. */
export function remainingFrom(resp) {
  if (!resp || !resp.active || !resp.state || !resp.state.endsAt) return 0;
  const end = Date.parse(resp.state.endsAt);
  const skew = (resp.receivedAt || Date.now()) - (resp.now || Date.now());
  return Math.max(0, end - (Date.now() - skew));
}

/**
 * Fills `ul` with links to the allowed items. `open(href)` is called on click
 * (popup: open a new tab; blocked page: navigate this tab).
 * Returns the number of items.
 */
export function renderAllowedList(ul, state, open) {
  ul.replaceChildren();
  const links = allowedLinks(state);
  for (const link of links) {
    const li = document.createElement('li');
    const a = document.createElement('a');
    a.href = link.href;
    a.textContent = link.label;
    a.title = link.href;
    a.addEventListener('click', (ev) => {
      ev.preventDefault();
      open(link.href);
    });
    const note = document.createElement('span');
    note.className = 'note';
    note.textContent = link.note;
    li.append(a, note);
    ul.append(li);
  }
  return links.length;
}
