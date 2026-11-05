// Cross-language contract: the exact bytes LockedBridge sends (pinned on the Swift side by
// Tests/LockedBridgeTests/WireFixtureTests.swift) must parse into an active state here, every
// website entry the app can store must be usable, and enforcement must behave as SPEC says.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { normalizeState, isSessionActive, isUrlAllowed, parseWebsiteEntry, remainingMs } from '../allowlist.js';
import { buildSubframeRules } from '../dnr.js';

const fx = JSON.parse(readFileSync(new URL('./bridge-state-fixture.json', import.meta.url), 'utf8'));
const ACTIVE_AT = Date.parse(fx.activeAt);
const EXPIRED_AT = Date.parse(fx.expiredAt);
const msg = JSON.parse(fx.wire);
const state = normalizeState(msg);

test('bridge state message parses into an active state', () => {
  assert.equal(msg.type, 'state');
  assert.equal(state.active, true);
  assert.equal(state.endsAt, '2026-11-05T13:00:00Z');
  assert.equal(state.websites.length, msg.websites.length, 'no website entry dropped by normalizeState');
  assert.deepEqual(state.youtubeVideoIds, ['dQw4w9WgXcQ', 'a-b_c-d_e-f']);
  assert.equal(isSessionActive(state, ACTIVE_AT), true);
  assert.equal(remainingMs(state, ACTIVE_AT), 30 * 60_000);
  assert.equal(isSessionActive(state, EXPIRED_AT), false, 'endsAt <= now is expired on both sides');
});

test('every website entry the app stores is accepted by parseWebsiteEntry', () => {
  for (const w of msg.websites) assert.notEqual(parseWebsiteEntry(w), null, JSON.stringify(w));
});

test('inactive message', () => {
  const inactive = normalizeState(JSON.parse(fx.inactiveWire));
  assert.deepEqual(inactive, { active: false });
  assert.equal(isUrlAllowed('https://example.com/', inactive, { now: ACTIVE_AT }), true);
});

test('allowed URLs', () => {
  for (const url of fx.allowed) assert.equal(isUrlAllowed(url, state, { now: ACTIVE_AT }), true, url);
});

test('blocked URLs', () => {
  for (const url of fx.blocked) assert.equal(isUrlAllowed(url, state, { now: ACTIVE_AT }), false, url);
});

test('sub-frame rules are built for every entry', () => {
  const rules = buildSubframeRules(state, { now: ACTIVE_AT });
  const domainRule = rules.find((r) => r.condition.requestDomains);
  assert.deepEqual(domainRule.condition.requestDomains.sort(), ['claude.ai', 'example.org', 'localhost']);
  // 1 block + 1 support hosts + 1 domains + 3 pages + 3 YouTube regexes (one chunk).
  assert.equal(rules.length, 9);
});
