// Checks that the sub-frame DNR rules agree with isUrlAllowed(..., {frameType: 'sub_frame'}).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildSubframeRules, BLOCK_PRIORITY, ALLOW_PRIORITY } from '../dnr.js';
import { isUrlAllowed, SUPPORT_HOSTS } from '../allowlist.js';

const NOW = Date.parse('2026-11-05T10:00:00Z');
const VID = 'dQw4w9WgXcQ';
const VID2 = 'Ab-_0123456';
const STATE = {
  type: 'state',
  active: true,
  endsAt: '2026-11-05T11:00:00Z',
  websites: [
    { url: 'https://claude.ai', scope: 'domain' },
    { url: 'www.example.org', scope: 'domain' },
    { url: 'https://docs.python.org/3/docs', scope: 'page' },
    { url: 'https://www.wikipedia.org/wiki/Focus/', scope: 'page' },
    { url: 'news.ycombinator.com', scope: 'page' },
    { url: 'https://site.dev/a.b(c)', scope: 'page' },
  ],
  youtubeVideoIds: [VID, VID2],
};

/** Minimal emulation of DNR matching for the rule shapes dnr.js produces. */
function dnrAllows(url, rules) {
  const u = new URL(url);
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return true; // DNR never sees these
  const requestUrl = u.href.replace(/#.*$/, ''); // requests carry no fragment
  const matching = rules.filter((r) => {
    const c = r.condition;
    if (!c.resourceTypes.includes('sub_frame')) return false;
    if (c.requestDomains) return c.requestDomains.some((d) => u.hostname === d || u.hostname.endsWith('.' + d));
    if (c.regexFilter) return new RegExp(c.regexFilter, c.isUrlFilterCaseSensitive ? '' : 'i').test(requestUrl);
    return true;
  });
  if (matching.length === 0) return true;
  const top = Math.max(...matching.map((r) => r.priority));
  return matching.some((r) => r.priority === top && r.action.type === 'allow');
}

const CORPUS = [
  'https://claude.ai/', 'https://www.claude.ai/x', 'https://api.claude.ai/v1?x=1', 'https://evilclaude.ai/', 'https://claude.ai.evil.com/',
  'https://example.org/', 'https://www.example.org/a', 'https://cdn.example.org/a', 'https://notexample.org/',
  'https://docs.python.org/3/docs', 'https://docs.python.org/3/docs/', 'https://docs.python.org/3/docs/x?y=1', 'https://docs.python.org/3/docsx',
  'https://www.docs.python.org/3/docs/a', 'https://sub.docs.python.org/3/docs', 'https://docs.python.org:8080/3/docs',
  'https://wikipedia.org/wiki/Focus', 'https://www.wikipedia.org/wiki/Focus/History', 'https://www.wikipedia.org/wiki/Focusing',
  'https://news.ycombinator.com/', 'https://news.ycombinator.com/item?id=1', 'https://x.news.ycombinator.com/',
  'https://site.dev/a.b(c)', 'https://site.dev/a.b(c)/d', 'https://site.dev/aXb(c)', 'https://site.dev/a.b(c)x',
  `https://www.youtube.com/embed/${VID}`, `https://www.youtube.com/embed/${VID}?autoplay=1&rel=0`, `https://youtube.com/embed/${VID2}`,
  `https://www.youtube.com/embed/aaaaaaaaaaa`, `https://www.youtube.com/embed/${VID}x`, `https://www.youtube-nocookie.com/embed/${VID}`,
  `https://www.youtube.com/watch?v=${VID}`, `https://www.youtube.com/watch?feature=x&v=${VID}&t=1`, `https://www.youtube.com/watch?v=aaaaaaaaaaa&v=${VID}`,
  `https://www.youtube.com/watch?vv=1&v=${VID}`, `https://www.youtube.com/watch?x=${VID}`, `https://m.youtube.com/watch?v=${VID2}`,
  `https://youtu.be/${VID}`, `https://youtu.be/${VID}?t=3`, `https://youtu.be/aaaaaaaaaaa`, `https://www.youtube.com/shorts/${VID}`,
  `https://www.youtube.com/live/${VID}`, 'https://www.youtube.com/', 'https://www.youtube.com/live_chat?v=' + VID,
  ...SUPPORT_HOSTS.map((h) => `https://${h}/path`), 'https://google.com/recaptcha', 'https://x.accounts.google.com/',
  'https://twitter.com/embed', 'https://js.stripe.com/v3/', 'http://claude.ai/', 'about:blank', 'data:text/html,hi',
];

test('DNR rules agree with isUrlAllowed for sub-frames', () => {
  const rules = buildSubframeRules(STATE, { now: NOW });
  for (const url of CORPUS) {
    if (url === 'https://x.accounts.google.com/') continue; // see below
    assert.equal(dnrAllows(url, rules), isUrlAllowed(url, STATE, { frameType: 'sub_frame', now: NOW }), url);
  }
  // Support hosts are exact in both.
  assert.equal(dnrAllows('https://x.accounts.google.com/', rules), false);
  assert.equal(isUrlAllowed('https://x.accounts.google.com/', STATE, { frameType: 'sub_frame', now: NOW }), false);
});

test('agreement holds with one ID per rule as well', () => {
  const rules = buildSubframeRules(STATE, { now: NOW, idsPerRule: 1 });
  for (const url of CORPUS) {
    assert.equal(dnrAllows(url, rules), isUrlAllowed(url, STATE, { frameType: 'sub_frame', now: NOW }), url);
  }
});

test('no rules when inactive or expired', () => {
  assert.deepEqual(buildSubframeRules({ active: false }, { now: NOW }), []);
  assert.deepEqual(buildSubframeRules(null, { now: NOW }), []);
  assert.deepEqual(buildSubframeRules({ ...STATE, endsAt: '2026-11-05T09:00:00Z' }, { now: NOW }), []);
});

test('rule shape: unique ids, one block rule, allow rules above it', () => {
  const rules = buildSubframeRules(STATE, { now: NOW });
  const ids = rules.map((r) => r.id);
  assert.equal(new Set(ids).size, ids.length);
  assert.ok(ids.every((id) => Number.isInteger(id) && id >= 1));
  const blocks = rules.filter((r) => r.action.type === 'block');
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].priority, BLOCK_PRIORITY);
  assert.ok(rules.filter((r) => r.action.type === 'allow').every((r) => r.priority === ALLOW_PRIORITY));
  assert.ok(rules.every((r) => r.condition.resourceTypes.length === 1 && r.condition.resourceTypes[0] === 'sub_frame'));
});

test('empty session still blocks sub-frames but allows support hosts', () => {
  const s = { active: true, endsAt: STATE.endsAt, websites: [], youtubeVideoIds: [] };
  const rules = buildSubframeRules(s, { now: NOW });
  assert.equal(dnrAllows('https://twitter.com/', rules), false);
  assert.equal(dnrAllows('https://accounts.google.com/', rules), true);
  assert.ok(!rules.some((r) => r.condition.requestDomains), 'no empty requestDomains rule');
});

test('regexes avoid features RE2 lacks (lookaround, backreferences)', () => {
  for (const r of buildSubframeRules(STATE, { now: NOW })) {
    if (!r.condition.regexFilter) continue;
    assert.doesNotMatch(r.condition.regexFilter, /\(\?[=!<]|\\[1-9]/);
  }
});
