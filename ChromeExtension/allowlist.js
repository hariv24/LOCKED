// Locked: URL allowlist semantics (SPEC.md, "URL allowlist semantics").
//
// Pure ES module: no chrome.* APIs, so it can be unit-tested in node.
// This is the ONLY place where the allowlist rules are implemented.

export const EXTENSION_ID = 'labfclmdkmlcipjlibjnohgahngindoo';

/** Rule 5: always-allowed login/asset hosts (exact host match). */
export const SUPPORT_HOSTS = Object.freeze([
  'accounts.google.com',
  'accounts.youtube.com',
  'ssl.gstatic.com',
  'www.gstatic.com',
  'auth.openai.com',
  'auth0.openai.com',
  'appleid.apple.com',
  'challenges.cloudflare.com',
  'consent.youtube.com',
  'consent.google.com',
]);

/** Rule 4: hosts on which an allowed YouTube video ID unlocks the URL. */
export const YOUTUBE_HOSTS = Object.freeze(['youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be']);

/** Rule 1: browser pages that stay blocked during a session (prefix match). */
export const BLOCKED_BROWSER_PAGE_PREFIXES = Object.freeze([
  'chrome://extensions',
  'chrome://settings',
  'chrome://flags',
]);

// ---------------------------------------------------------------------------
// Session state
// ---------------------------------------------------------------------------

/**
 * Normalizes a bridge `state` message into
 * `{active:false}` or `{active:true, endsAt, websites:[{url,scope}], youtubeVideoIds:[...]}`.
 * Malformed entries are dropped.
 */
export function normalizeState(msg) {
  if (!msg || typeof msg !== 'object' || msg.active !== true) return { active: false };
  const websites = Array.isArray(msg.websites)
    ? msg.websites
        .filter((w) => w && typeof w.url === 'string' && (w.scope === 'page' || w.scope === 'domain'))
        .map((w) => ({ url: w.url, scope: w.scope }))
    : [];
  const youtubeVideoIds = Array.isArray(msg.youtubeVideoIds)
    ? msg.youtubeVideoIds.filter((id) => typeof id === 'string')
    : [];
  return { active: true, endsAt: typeof msg.endsAt === 'string' ? msg.endsAt : null, websites, youtubeVideoIds };
}

/** Milliseconds since epoch for `endsAt`, or NaN. */
export function endsAtMs(state) {
  if (!state || typeof state.endsAt !== 'string') return NaN;
  return Date.parse(state.endsAt);
}

/**
 * A session is active iff `active === true` and `endsAt` parses and is in the future.
 * A missing/unparseable or past `endsAt` counts as inactive (fail open, like a disconnected bridge).
 */
export function isSessionActive(state, now = Date.now()) {
  if (!state || state.active !== true) return false;
  const end = endsAtMs(state);
  return Number.isFinite(end) && end > toMs(now);
}

/** Remaining milliseconds of an active session, else 0. */
export function remainingMs(state, now = Date.now()) {
  if (!isSessionActive(state, now)) return 0;
  return endsAtMs(state) - toMs(now);
}

function toMs(now) {
  return now instanceof Date ? now.getTime() : Number(now);
}

// ---------------------------------------------------------------------------
// YouTube video IDs (mirror of Sources/LockedShared/YouTubeURL.swift)
// ---------------------------------------------------------------------------

const ID_RE = /^[A-Za-z0-9_-]{11}$/;

/** `YouTubeURL.isValidId`: exactly 11 chars of [A-Za-z0-9_-]. */
export function isValidYouTubeId(s) {
  return typeof s === 'string' && ID_RE.test(s);
}

// Swift's CharacterSet.whitespacesAndNewlines: Unicode Z* categories + U+0009...U+000D + U+0085.
// (JS's String.prototype.trim differs: it also strips U+FEFF and does not strip U+0085.)
const SWIFT_WS = '[\\t\\n\\v\\f\\r\\u0085 \\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000]';
const SWIFT_TRIM_RE = new RegExp(`^${SWIFT_WS}+|${SWIFT_WS}+$`, 'g');

// Strict RFC 3986 tokenizer, mirroring Foundation's URLComponents(string:), which returns nil
// for strings with characters that are invalid in their component (spaces, '|', '{', non-ASCII,
// bad percent escapes, ...). WHATWG `new URL()` is far more lenient, so it is NOT used here.
const PCT = '%[0-9A-Fa-f]{2}';
const UNRESERVED = 'A-Za-z0-9\\-._~';
const SUB_DELIMS = "!$&'()*+,;=";
const PCHAR = `(?:[${UNRESERVED}${SUB_DELIMS}:@]|${PCT})`;
const SCHEME_RE = /^[A-Za-z][A-Za-z0-9+.-]*$/;
const USERINFO_RE = new RegExp(`^(?:[${UNRESERVED}${SUB_DELIMS}:]|${PCT})*$`);
const REG_NAME_RE = new RegExp(`^(?:[${UNRESERVED}${SUB_DELIMS}]|${PCT})*$`);
const IP_LITERAL_RE = /^\[[0-9A-Fa-f:.]+\]$/;
const PORT_RE = /^[0-9]*$/;
const PATH_RE = new RegExp(`^(?:${PCHAR}|/)*$`);
const QUERY_RE = new RegExp(`^(?:${PCHAR}|[/?])*$`);
const URI_RE = /^(?:([^:/?#]+):)?(?:\/\/([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?$/s;

function pctDecode(s) {
  try {
    return decodeURIComponent(s);
  } catch {
    return null;
  }
}

/** Returns {host, path, query} like URLComponents (host/path decoded, query raw), or null if invalid. */
function strictParse(str) {
  const m = URI_RE.exec(str);
  if (!m) return null;
  const [, scheme, authority, path, query, fragment] = m;
  if (scheme !== undefined && !SCHEME_RE.test(scheme)) return null;
  if (!PATH_RE.test(path)) return null;
  if (query !== undefined && !QUERY_RE.test(query)) return null;
  if (fragment !== undefined && !QUERY_RE.test(fragment)) return null;
  if (authority === undefined) return { host: null, path: pctDecode(path) ?? '', query: query ?? null };

  const at = authority.lastIndexOf('@');
  const userinfo = at >= 0 ? authority.slice(0, at) : null;
  const hostport = authority.slice(at + 1);
  if (userinfo !== null && !USERINFO_RE.test(userinfo)) return null;
  let host;
  let port;
  if (hostport.startsWith('[')) {
    const close = hostport.indexOf(']');
    if (close < 0) return null;
    host = hostport.slice(0, close + 1);
    const rest = hostport.slice(close + 1);
    if (rest !== '' && !rest.startsWith(':')) return null;
    port = rest.slice(1);
    if (!IP_LITERAL_RE.test(host)) return null;
  } else {
    const colon = hostport.indexOf(':');
    host = colon >= 0 ? hostport.slice(0, colon) : hostport;
    port = colon >= 0 ? hostport.slice(colon + 1) : '';
    if (!REG_NAME_RE.test(host)) return null;
  }
  if (!PORT_RE.test(port)) return null;
  const decodedHost = pctDecode(host);
  if (decodedHost === null) return null;
  return { host: decodedHost, path: pctDecode(path) ?? '', query: query ?? null };
}

/** URLComponents.queryItems.first(where: name == wanted)?.value (percent-decoded, '+' kept). */
function firstQueryValue(rawQuery, wanted) {
  if (rawQuery === null || rawQuery === undefined) return null;
  for (const item of rawQuery.split('&')) {
    const eq = item.indexOf('=');
    const name = pctDecode(eq >= 0 ? item.slice(0, eq) : item);
    if (name === wanted) return eq >= 0 ? pctDecode(item.slice(eq + 1)) : null;
  }
  return null;
}

/** Shared core of the Swift `videoId(from:)` switch. `path` must already be percent-decoded. */
function videoIdFromComponents(rawHost, path, rawQuery) {
  if (typeof rawHost !== 'string') return null;
  const lower = rawHost.toLowerCase();
  const host = lower.startsWith('www.') ? lower.slice(4) : lower;
  const parts = path.split('/').filter((p) => p.length > 0);
  let id = null;
  switch (host) {
    case 'youtu.be':
      id = parts.length > 0 ? parts[0] : null;
      break;
    case 'youtube.com':
    case 'm.youtube.com':
    case 'music.youtube.com':
    case 'youtube-nocookie.com':
      if (parts[0] === 'watch' || path === '/watch') {
        id = firstQueryValue(rawQuery, 'v');
      } else if (parts.length >= 2 && ['embed', 'shorts', 'live', 'v'].includes(parts[0])) {
        id = parts[1];
      }
      break;
    default:
      return null;
  }
  return isValidYouTubeId(id) ? id : null;
}

/**
 * Exact JS port of `YouTubeURL.videoId(from:)`: extracts the 11-char video ID from watch,
 * youtu.be, embed, shorts, live and /v/ URLs (youtube.com, m., music., youtube-nocookie.com,
 * each optionally with www.). A bare 11-char ID is accepted too. Returns null otherwise.
 */
export function youtubeVideoId(input) {
  if (typeof input !== 'string') return null;
  const trimmed = input.replace(SWIFT_TRIM_RE, '');
  if (isValidYouTubeId(trimmed)) return trimmed;
  const candidate = trimmed.includes('://') ? trimmed : 'https://' + trimmed;
  const comps = strictParse(candidate);
  if (!comps || comps.host === null) return null;
  return videoIdFromComponents(comps.host, comps.path, comps.query);
}

/**
 * Same logic as youtubeVideoId, applied to an already-parsed WHATWG URL (what Chrome hands us).
 * Used for enforcement so that characters Chrome legitimately leaves unescaped in a navigation URL
 * (e.g. '|' in a query string) can't make an allowed video look invalid.
 */
function videoIdFromUrlObject(u) {
  const path = pctDecode(u.pathname) ?? '';
  const query = u.search ? u.search.slice(1) : null;
  return videoIdFromComponents(u.hostname, path, query);
}

// ---------------------------------------------------------------------------
// Website entries
// ---------------------------------------------------------------------------

/**
 * Strips one leading "www." (rules 2 and 3). Guard: only if what remains still has a dot, so an
 * entry like "www.com" can't turn into "com" and allow every .com site.
 */
export function stripWww(host) {
  if (host.startsWith('www.') && host.slice(4).includes('.')) return host.slice(4);
  return host;
}

function stripTrailingSlashes(path) {
  return path.replace(/\/+$/, '');
}

const entryCache = new Map();

/**
 * Parses a WebsiteEntry into {scope, host, path}: host lowercased with www. stripped, path
 * normalized by the URL parser with trailing slashes removed ("" for the root). The app may store
 * entries without a scheme ("claude.ai/docs"); "https://" is assumed then. Returns null if unusable.
 */
export function parseWebsiteEntry(entry) {
  if (!entry || typeof entry.url !== 'string') return null;
  if (entry.scope !== 'domain' && entry.scope !== 'page') return null;
  const cacheKey = entry.scope + ' ' + entry.url;
  if (entryCache.has(cacheKey)) return entryCache.get(cacheKey);
  let parsed = null;
  let raw = entry.url.trim();
  if (raw !== '') {
    if (!raw.includes('://')) raw = 'https://' + raw;
    try {
      const u = new URL(raw);
      if ((u.protocol === 'http:' || u.protocol === 'https:') && u.hostname) {
        parsed = { scope: entry.scope, host: stripWww(u.hostname.toLowerCase()), path: stripTrailingSlashes(u.pathname) };
      }
    } catch {
      parsed = null;
    }
  }
  if (entryCache.size > 1000) entryCache.clear();
  entryCache.set(cacheKey, parsed);
  return parsed;
}

/** Rule 3 path test: equal, or a descendant ("/docs" covers "/docs/x" but not "/docsx"). */
export function pagePathMatches(urlPath, entryPath) {
  const p = stripTrailingSlashes(urlPath);
  return p === entryPath || p.startsWith(entryPath + '/');
}

/** Rule 2 host test: equal or a subdomain, both sides www.-stripped. */
export function domainMatches(urlHost, entryHost) {
  const bare = stripWww(urlHost.toLowerCase());
  return bare === entryHost || bare.endsWith('.' + entryHost);
}

// ---------------------------------------------------------------------------
// The rule engine
// ---------------------------------------------------------------------------

/**
 * Is a navigation to `urlString` allowed under `state`?
 *
 * @param {string} urlString  navigation URL (as Chrome reports it)
 * @param {object} state      bridge state ({active, endsAt, websites, youtubeVideoIds}) or null
 * @param {object} [opts]
 * @param {string} [opts.frameType='main_frame']  'main_frame' | 'sub_frame' | anything else = sub-resource
 * @param {string} [opts.extensionId]             this extension's ID (chrome.runtime.id)
 * @param {number|Date} [opts.now]                current time (for tests)
 */
export function isUrlAllowed(urlString, state, { frameType = 'main_frame', extensionId = EXTENSION_ID, now = Date.now() } = {}) {
  // No active session (or expired endsAt): everything is allowed.
  if (!isSessionActive(state, now)) return true;
  // Rule 6: only main_frame / sub_frame navigations are ever blocked.
  if (frameType !== 'main_frame' && frameType !== 'sub_frame') return true;

  let u;
  try {
    u = new URL(String(urlString));
  } catch {
    return false; // unparseable navigation during a session: fail closed
  }

  const scheme = u.protocol.toLowerCase();
  if (scheme !== 'http:' && scheme !== 'https:') return nonWebAllowed(u, frameType, extensionId);

  const host = u.hostname.toLowerCase();

  // Rule 5: support hosts.
  if (SUPPORT_HOSTS.includes(host)) return true;

  // Rules 2 and 3: website entries.
  for (const entry of state.websites || []) {
    const e = parseWebsiteEntry(entry);
    if (!e) continue;
    if (e.scope === 'domain') {
      if (domainMatches(host, e.host)) return true;
    } else if (stripWww(host) === e.host && pagePathMatches(u.pathname, e.path)) {
      return true;
    }
  }

  // Rule 4: allowed YouTube videos (watch, youtu.be, embed, shorts, live, /v/).
  if (YOUTUBE_HOSTS.includes(host)) {
    const id = videoIdFromUrlObject(u);
    if (id !== null && (state.youtubeVideoIds || []).includes(id)) return true;
  }

  return false;
}

/** Rule 1: non-http(s) schemes. */
function nonWebAllowed(u, frameType, extensionId) {
  const scheme = u.protocol.toLowerCase();
  if (scheme === 'chrome-extension:' && u.hostname.toLowerCase() === String(extensionId).toLowerCase()) return true;
  const href = u.href.toLowerCase();
  if (BLOCKED_BROWSER_PAGE_PREFIXES.some((prefix) => href.startsWith(prefix))) return false;
  const isAboutBlank = scheme === 'about:' && u.pathname.toLowerCase() === 'blank';
  // about:blank is allowed everywhere (login pop-ups open blank, then redirect); data: only in sub-frames.
  if (isAboutBlank) return true;
  if (scheme === 'data:') return frameType === 'sub_frame';
  return true;
}

/** URL of the page a blocked main frame is redirected to. */
export function blockedPageUrl(blockedUrl, extensionId = EXTENSION_ID) {
  return `chrome-extension://${extensionId}/blocked.html?url=${encodeURIComponent(blockedUrl)}`;
}
