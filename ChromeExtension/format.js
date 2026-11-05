// Locked: small pure helpers shared by background, popup and blocked page.

/** "1:04:09" / "4:09" style countdown. */
export function formatClock(ms) {
  const total = Math.max(0, Math.ceil(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

/** Badge text (max 4 chars): "25m", "1h05", "<1m", or "" when nothing remains. */
export function formatBadge(ms) {
  if (!(ms > 0)) return '';
  const minutes = Math.ceil(ms / 60000);
  if (minutes < 1) return '<1m';
  if (minutes < 60) return `${minutes}m`;
  const h = Math.floor(minutes / 60);
  if (h >= 10) return `${h}h`;
  return `${h}h${String(minutes % 60).padStart(2, '0')}`;
}

/**
 * Turns a session state into clickable links: [{label, href, kind}].
 * Only http(s) hrefs are produced.
 */
export function allowedLinks(state) {
  const links = [];
  if (!state || state.active !== true) return links;
  for (const w of state.websites || []) {
    if (!w || typeof w.url !== 'string') continue;
    const raw = w.url.trim();
    let href;
    try {
      const u = new URL(raw.includes('://') ? raw : 'https://' + raw);
      if (u.protocol !== 'http:' && u.protocol !== 'https:') continue;
      href = u.href;
    } catch {
      continue;
    }
    const label = raw.replace(/^https?:\/\//i, '').replace(/\/$/, '');
    links.push({ kind: 'website', label, href, note: w.scope === 'domain' ? 'whole site' : 'this page' });
  }
  for (const id of state.youtubeVideoIds || []) {
    if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{11}$/.test(id)) continue;
    links.push({ kind: 'youtube', label: `YouTube video ${id}`, href: `https://www.youtube.com/watch?v=${id}`, note: 'video' });
  }
  return links;
}
