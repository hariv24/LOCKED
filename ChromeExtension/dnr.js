// Locked: sub-frame enforcement as declarativeNetRequest session rules.
//
// Pure ES module (no chrome.* calls) so it can be tested in node.
//
// Why DNR for sub-frames: webNavigation can only observe a frame navigation; it can't cancel it,
// and redirecting a specific iframe from the service worker is racy. DNR rules are evaluated by the
// browser's network stack before the request is sent, keep working while the service worker is
// asleep, and need no extra permissions. The rules are a translation of the SPEC rules in
// allowlist.js restricted to what a sub_frame *request* can be (http/https only; about:blank,
// data:, chrome-extension:// frames never hit the network so DNR doesn't apply, which matches
// rule 1). tests/dnr.test.mjs checks that these rules agree with isUrlAllowed on a URL corpus.
//
//   priority 1: block every sub_frame request
//   priority 2: allow sub_frames matching rule 2 (domain), 3 (page), 4 (YouTube IDs), 5 (support hosts)

import { isSessionActive, parseWebsiteEntry, SUPPORT_HOSTS, isValidYouTubeId } from './allowlist.js';

export const BLOCK_PRIORITY = 1;
export const ALLOW_PRIORITY = 2;

const SUB_FRAME = ['sub_frame'];
const USERINFO = '(?:[^/?#@]*@)?';
const PORT = '(?::[0-9]+)?';
const END = '(?:[/?#]|$)';

export function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function allowRegex(regexFilter) {
  return {
    priority: ALLOW_PRIORITY,
    action: { type: 'allow' },
    condition: { regexFilter, isUrlFilterCaseSensitive: true, resourceTypes: SUB_FRAME },
  };
}

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

/** Regexes (one per chunk of IDs) matching the YouTube URLs rule 4 accepts for those IDs. */
export function youtubeRegexes(ids) {
  const alt = `(?:${ids.join('|')})`;
  // Query params before the first v=... must not be named "v" (Swift takes the first "v" item).
  const priorParams = '(?:(?:[^&#v][^&#]*|v[^&#=][^&#]*)?&)*';
  return [
    `^https?://${USERINFO}(?:www\\.|m\\.)?youtube\\.com${PORT}/+(?:embed|shorts|live|v)/+${alt}${END}`,
    `^https?://${USERINFO}(?:www\\.|m\\.)?youtube\\.com${PORT}/+watch(?:/[^?#]*)?\\?${priorParams}v=${alt}(?:[&#]|$)`,
    `^https?://${USERINFO}youtu\\.be${PORT}/+${alt}${END}`,
  ];
}

/**
 * Builds the DNR session rules for `state`. Returns [] when no session is active.
 * @param {object} state
 * @param {{now?: number, idsPerRule?: number, firstId?: number}} [opts]
 */
export function buildSubframeRules(state, { now = Date.now(), idsPerRule = 8, firstId = 1 } = {}) {
  if (!isSessionActive(state, now)) return [];
  const rules = [
    { priority: BLOCK_PRIORITY, action: { type: 'block' }, condition: { resourceTypes: SUB_FRAME } },
  ];

  // Rule 5: support hosts (exact host).
  rules.push(allowRegex(`^https?://${USERINFO}(?:${SUPPORT_HOSTS.map(escapeRegex).join('|')})${PORT}${END}`));

  // Rule 2: domain scope. requestDomains matches the domain and all its subdomains, which equals
  // "www.-stripped host equals entry host or is a subdomain of it" (entry hosts are already stripped).
  const domains = new Set();
  const pages = [];
  for (const entry of state.websites || []) {
    const e = parseWebsiteEntry(entry);
    if (!e) continue;
    if (e.scope === 'domain') domains.add(e.host);
    else pages.push(e);
  }
  if (domains.size > 0) {
    rules.push({
      priority: ALLOW_PRIORITY,
      action: { type: 'allow' },
      condition: { requestDomains: [...domains], resourceTypes: SUB_FRAME },
    });
  }

  // Rule 3: page scope. Same host (optionally www.), path equal or a descendant.
  const seenPages = new Set();
  for (const e of pages) {
    const key = e.host + e.path;
    if (seenPages.has(key)) continue;
    seenPages.add(key);
    const hostRe = '(?:www\\.)?' + escapeRegex(e.host);
    rules.push(allowRegex(`^https?://${USERINFO}${hostRe}${PORT}${escapeRegex(e.path)}${END}`));
  }

  // Rule 4: YouTube video IDs (chunked so each regex stays under DNR's compiled-size limit).
  const ids = [...new Set((state.youtubeVideoIds || []).filter(isValidYouTubeId))];
  for (const group of chunk(ids, Math.max(1, idsPerRule))) {
    for (const re of youtubeRegexes(group)) rules.push(allowRegex(re));
  }

  return rules.map((r, i) => ({ id: firstId + i, ...r }));
}
