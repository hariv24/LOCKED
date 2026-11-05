// Locked: toolbar popup. Connection status, remaining time and the allowed items.

import { formatClock } from './format.js';
import { fetchState, remainingFrom, renderAllowedList } from './ui.js';

const $ = (id) => document.getElementById(id);
let latest = null;

function openTab(href) {
  chrome.tabs.create({ url: href });
  window.close();
}

function render() {
  if (!latest) return;
  const conn = $('conn');
  const statusText = { connected: 'Connected', connecting: 'Connecting…', disconnected: 'Not connected' };
  conn.textContent = statusText[latest.status] || 'Not connected';
  conn.className = 'pill ' + (latest.status === 'connected' ? 'ok' : latest.status === 'disconnected' ? 'off' : '');

  const remaining = remainingFrom(latest);
  const active = remaining > 0;
  $('active').hidden = !active;
  $('idle').hidden = active;
  if (active) {
    $('remaining').textContent = formatClock(remaining);
  } else {
    $('idle-text').textContent =
      latest.status === 'disconnected'
        ? 'Not connected to the Locked app. Open Locked on this Mac; browsing is not filtered until it connects.'
        : 'No focus session is running.';
  }
}

async function load() {
  latest = await fetchState();
  const count = renderAllowedList($('allowed'), latest.active ? latest.state : null, openTab);
  $('none').hidden = count > 0;
  render();
}

load();
setInterval(render, 1000);
setInterval(load, 5000);
