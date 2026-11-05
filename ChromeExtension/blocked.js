// Locked: blocked page. Shows what was blocked, how long the session has left and what's allowed.

import { formatClock } from './format.js';
import { fetchState, remainingFrom, renderAllowedList } from './ui.js';

const $ = (id) => document.getElementById(id);
const blockedUrl = new URLSearchParams(location.search).get('url') || '';

let latest = null;

function navigate(href) {
  // Navigate this tab; the background re-checks the destination like any other navigation.
  chrome.tabs.getCurrent((tab) => {
    if (tab && tab.id !== undefined) chrome.tabs.update(tab.id, { url: href });
    else location.href = href;
  });
}

function isSafeTarget(href) {
  try {
    return !/^(javascript|data|blob):/i.test(new URL(href).protocol);
  } catch {
    return false;
  }
}

function render() {
  const resp = latest;
  if (!resp) return;
  const remaining = remainingFrom(resp);
  const active = remaining > 0;

  $('blocked-url').textContent = blockedUrl;
  $('blocked-url').hidden = !blockedUrl;
  $('session').hidden = !active;
  $('over').hidden = active;
  $('hint').hidden = !active;

  if (active) {
    $('remaining').textContent = formatClock(remaining);
    const end = new Date(resp.state.endsAt);
    $('ends-at').textContent = `at ${end.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`;
    document.title = `Blocked by Locked · ${formatClock(remaining)}`;
  } else {
    document.title = 'Blocked by Locked';
    const link = $('continue');
    link.hidden = !(blockedUrl && isSafeTarget(blockedUrl));
    link.parentElement.hidden = link.hidden;
  }
}

async function load() {
  latest = await fetchState();
  const count = renderAllowedList($('allowed'), latest.active ? latest.state : null, navigate);
  $('allowed-section').hidden = count === 0;
  render();
}

$('continue').addEventListener('click', (ev) => {
  ev.preventDefault();
  if (isSafeTarget(blockedUrl)) navigate(blockedUrl);
});

load();
setInterval(render, 1000);
setInterval(load, 10_000);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') load();
});
