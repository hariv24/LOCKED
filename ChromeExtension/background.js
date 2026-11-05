// Locked: MV3 service worker.
//
// - Talks to the native host `app.locked.bridge` (SPEC "Native messaging protocol").
// - Enforces the allowlist (allowlist.js) on main-frame navigations by redirecting the tab to
//   blocked.html, and on sub-frames via declarativeNetRequest session rules (dnr.js).
// - Disconnected bridge or no active session => allow everything (the app enforces fail-closed
//   by hiding Chrome when the bridge heartbeat goes stale).

import { isUrlAllowed, isSessionActive, normalizeState, remainingMs } from './allowlist.js';
import { buildSubframeRules } from './dnr.js';
import { formatBadge } from './format.js';

const NATIVE_HOST = 'app.locked.bridge';
const VERSION = chrome.runtime.getManifest().version;
const EXTENSION_ID = chrome.runtime.id;
const PING_MS = 20_000;
const BACKOFF_MIN_MS = 1_000;
const BACKOFF_MAX_MS = 30_000;
const ALARM = 'locked-tick';
const ALARM_PERIOD_MIN = 0.5; // 30s: the minimum Chrome allows for alarms
const STORAGE_KEY = 'lockedState';
const BADGE_COLOR = '#3b5bdb';

/** @type {chrome.runtime.Port | null} */
let port = null;
/** 'connecting' (worker just started or reconnecting) | 'connected' (got a state) | 'disconnected' */
let status = 'connecting';
/** Last state from the bridge (normalized). Restored from storage.session on worker start. */
let bridgeState = { active: false };
let backoffMs = BACKOFF_MIN_MS;
let reconnectTimer = null;
let pingTimer = null;
let expiryTimer = null;
let appliedRulesKey = null;
let lastYouTubeClean = null;
const recentRedirects = new Map(); // tabId -> {url, t}

// Restore the cached state so a restarted worker keeps enforcing while it reconnects. If the
// reconnect fails we go to 'disconnected' and allow everything, per SPEC.
const ready = (async () => {
  try {
    const got = await chrome.storage.session.get(STORAGE_KEY);
    if (got && got[STORAGE_KEY]) bridgeState = normalizeState(got[STORAGE_KEY]);
  } catch (e) {
    console.warn('[Locked] could not restore state', e);
  }
})();

function effectiveState() {
  return status === 'disconnected' ? { active: false } : bridgeState;
}

// ---------------------------------------------------------------------------
// Native messaging
// ---------------------------------------------------------------------------

function connect() {
  if (port) return;
  clearTimeout(reconnectTimer);
  reconnectTimer = null;
  let p;
  try {
    p = chrome.runtime.connectNative(NATIVE_HOST);
  } catch (e) {
    console.warn('[Locked] connectNative threw', e);
    onPortGone(null);
    return;
  }
  port = p;
  if (status === 'disconnected') status = 'connecting';
  p.onMessage.addListener((msg) => onBridgeMessage(p, msg));
  p.onDisconnect.addListener(() => {
    const err = chrome.runtime.lastError;
    if (err) console.warn('[Locked] bridge disconnected:', err.message);
    onPortGone(p);
  });
  safePost(p, { type: 'hello', version: VERSION });
  clearInterval(pingTimer);
  pingTimer = setInterval(() => {
    if (port === p) safePost(p, { type: 'ping' });
  }, PING_MS);
}

function safePost(p, msg) {
  try {
    p.postMessage(msg);
  } catch (e) {
    console.warn('[Locked] postMessage failed', e);
  }
}

function onPortGone(p) {
  if (p && port !== p) return;
  port = null;
  clearInterval(pingTimer);
  pingTimer = null;
  status = 'disconnected';
  setState({ active: false });
  scheduleReconnect();
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  const delay = backoffMs;
  backoffMs = Math.min(backoffMs * 2, BACKOFF_MAX_MS);
  // If the worker is suspended before this fires, the alarm below reconnects instead.
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, delay);
}

function onBridgeMessage(p, msg) {
  if (port !== p || !msg || typeof msg !== 'object') return;
  if (msg.type === 'state') {
    status = 'connected';
    backoffMs = BACKOFF_MIN_MS;
    setState(normalizeState(msg));
  }
}

function setState(state) {
  bridgeState = state;
  chrome.storage.session.set({ [STORAGE_KEY]: state }).catch((e) => console.warn('[Locked] storage', e));
  return queueRefresh();
}

// ---------------------------------------------------------------------------
// Applying state: DNR rules, badge, YouTube tabs, re-check of all tabs
// ---------------------------------------------------------------------------

let refreshChain = Promise.resolve();

/** Serialized so DNR updates never interleave. */
function queueRefresh() {
  refreshChain = refreshChain.then(refresh).catch((e) => console.warn('[Locked] refresh failed', e));
  return refreshChain;
}

async function refresh() {
  await ready;
  const state = effectiveState();
  const active = isSessionActive(state);
  scheduleExpiry(state);
  await Promise.allSettled([syncSubframeRules(state), updateBadge(state), notifyYouTubeTabs(state)]);
  if (active) await enforceAllTabs();
}

function scheduleExpiry(state) {
  clearTimeout(expiryTimer);
  expiryTimer = null;
  const ms = remainingMs(state);
  // The bridge also sends active:false on expiry; this is a local backstop.
  if (ms > 0) expiryTimer = setTimeout(queueRefresh, Math.min(ms + 250, 2 ** 31 - 1));
}

async function syncSubframeRules(state) {
  let rules = buildSubframeRules(state);
  let supported = await filterSupportedRegexRules(rules);
  if (supported.length !== rules.length) {
    // Most likely a YouTube regex exceeded DNR's memory limit: retry with one ID per rule.
    rules = buildSubframeRules(state, { idsPerRule: 1 });
    supported = await filterSupportedRegexRules(rules);
  }
  const key = JSON.stringify(supported);
  if (key === appliedRulesKey) return;
  const existing = await chrome.declarativeNetRequest.getSessionRules();
  try {
    await chrome.declarativeNetRequest.updateSessionRules({
      removeRuleIds: existing.map((r) => r.id),
      addRules: supported,
    });
    appliedRulesKey = key;
  } catch (e) {
    // Never leave a stale "block all sub-frames" rule behind: clear everything (fail open).
    console.warn('[Locked] updateSessionRules failed; clearing sub-frame rules', e);
    await chrome.declarativeNetRequest.updateSessionRules({ removeRuleIds: existing.map((r) => r.id) }).catch(() => {});
    appliedRulesKey = null;
  }
}

const regexSupportCache = new Map();

async function filterSupportedRegexRules(rules) {
  const out = [];
  for (const rule of rules) {
    const regex = rule.condition.regexFilter;
    if (!regex) {
      out.push(rule);
      continue;
    }
    let ok = regexSupportCache.get(regex);
    if (ok === undefined) {
      try {
        const res = await chrome.declarativeNetRequest.isRegexSupported({ regex, isCaseSensitive: true });
        ok = !!res.isSupported;
        if (!ok) console.warn('[Locked] unsupported DNR regex', res.reason, regex);
      } catch {
        ok = true; // API unavailable: let updateSessionRules decide
      }
      regexSupportCache.set(regex, ok);
    }
    if (ok) out.push(rule);
  }
  return out;
}

async function updateBadge(state) {
  const ms = remainingMs(state);
  const text = formatBadge(ms);
  await chrome.action.setBadgeBackgroundColor({ color: BADGE_COLOR });
  await chrome.action.setBadgeText({ text });
  const title =
    status === 'disconnected'
      ? 'Locked: not connected to the Locked app'
      : ms > 0
        ? `Locked: session active (${text} left)`
        : 'Locked: no active session';
  await chrome.action.setTitle({ title });
}

/** YouTube cleanup applies during a session unless YouTube as a whole is allowlisted. */
function youtubeClean(state) {
  return isSessionActive(state) && !isUrlAllowed('https://www.youtube.com/', state, { extensionId: EXTENSION_ID });
}

async function notifyYouTubeTabs(state) {
  const clean = youtubeClean(state);
  if (clean === lastYouTubeClean) return;
  lastYouTubeClean = clean;
  const tabs = await chrome.tabs.query({ url: ['*://*.youtube.com/*'] });
  for (const tab of tabs) {
    chrome.tabs.sendMessage(tab.id, { type: 'youtubeMode', clean }).catch(() => {});
  }
}

async function enforceAllTabs() {
  const tabs = await chrome.tabs.query({});
  for (const tab of tabs) {
    const url = tab.url || tab.pendingUrl;
    if (url) checkMainFrame(tab.id, url);
  }
}

// ---------------------------------------------------------------------------
// Main-frame enforcement
// ---------------------------------------------------------------------------

async function checkMainFrame(tabId, url) {
  await ready;
  if (typeof tabId !== 'number' || tabId < 0 || !url) return;
  const state = effectiveState();
  if (!isSessionActive(state)) return;
  if (isUrlAllowed(url, state, { frameType: 'main_frame', extensionId: EXTENSION_ID })) return;
  redirectToBlocked(tabId, url);
}

async function redirectToBlocked(tabId, url) {
  const now = Date.now();
  const last = recentRedirects.get(tabId);
  if (last && last.url === url && now - last.t < 1500) return; // several events fire per navigation
  recentRedirects.set(tabId, { url, t: now });
  const target = chrome.runtime.getURL('blocked.html') + '?url=' + encodeURIComponent(url);
  // tabs.update can fail transiently (e.g. "user may be dragging a tab"), so retry. Note: for
  // chrome:// pages (extensions/settings/flags) and incognito tabs (extension pages can't load in
  // incognito for a "spanning" extension) this may not always work; in incognito the tab ends up
  // on an error page, which still blocks. If every attempt throws, close the tab (fail closed).
  for (const delay of [0, 300, 1000, 3000]) {
    if (delay) await new Promise((r) => setTimeout(r, delay));
    if (delay && !isSessionActive(effectiveState())) return;
    try {
      await chrome.tabs.update(tabId, { url: target });
      return;
    } catch (e) {
      if (/no tab with id/i.test(String(e && e.message))) return;
    }
  }
  chrome.tabs.remove(tabId).catch(() => {});
}

// webNavigation: frameId 0 is the main frame. Non-zero frameIds are sub-frames (handled by the DNR
// rules) or prerendered pages; a prerendered page is re-checked via tabs.onUpdated when it's
// activated, because redirecting at prerender time would navigate the visible tab.
function onNav(details) {
  if (details.frameId === 0) checkMainFrame(details.tabId, details.url);
}
chrome.webNavigation.onBeforeNavigate.addListener(onNav);
chrome.webNavigation.onCommitted.addListener(onNav);
// YouTube is a single-page app: in-page navigations only show up here and in tabs.onUpdated.
chrome.webNavigation.onHistoryStateUpdated.addListener(onNav);

// Also catches URLs webNavigation doesn't report, notably chrome://extensions, chrome://settings
// and chrome://flags. Redirecting away from those works in current Chrome but isn't guaranteed.
chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.url) checkMainFrame(tabId, changeInfo.url);
});
chrome.tabs.onReplaced.addListener((addedTabId) => {
  chrome.tabs
    .get(addedTabId)
    .then((tab) => checkMainFrame(addedTabId, tab.url || tab.pendingUrl))
    .catch(() => {});
});
chrome.tabs.onRemoved.addListener((tabId) => recentRedirects.delete(tabId));

// ---------------------------------------------------------------------------
// Messages from popup, blocked page and the YouTube content script
// ---------------------------------------------------------------------------

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || typeof msg !== 'object' || sender.id !== EXTENSION_ID) return false;
  if (msg.type === 'getState') {
    ready.then(() => {
      const state = effectiveState();
      const active = isSessionActive(state);
      sendResponse({
        status,
        connected: status === 'connected',
        active,
        now: Date.now(),
        state: active ? state : { active: false },
      });
    });
    if (!port) connect();
    return true;
  }
  if (msg.type === 'getYouTubeMode') {
    ready.then(() => sendResponse({ clean: youtubeClean(effectiveState()) }));
    return true;
  }
  return false;
});

// ---------------------------------------------------------------------------
// Wake-ups: alarms as a backstop (reconnect, badge, expiry, re-check tabs)
// ---------------------------------------------------------------------------

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name !== ALARM) return;
  await ready;
  if (!port) connect();
  queueRefresh();
});

async function ensureAlarm() {
  const existing = await chrome.alarms.get(ALARM);
  if (!existing) await chrome.alarms.create(ALARM, { periodInMinutes: ALARM_PERIOD_MIN });
}

// Registering these makes Chrome start the worker at browser start / install; the top-level code
// below does the actual work on every worker start.
chrome.runtime.onStartup.addListener(() => {});
chrome.runtime.onInstalled.addListener(() => {});

ready.then(() => {
  ensureAlarm().catch((e) => console.warn('[Locked] alarm', e));
  connect();
  queueRefresh();
});
