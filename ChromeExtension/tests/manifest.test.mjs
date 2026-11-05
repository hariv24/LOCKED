import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, existsSync } from 'node:fs';
import { EXTENSION_ID } from '../allowlist.js';
import { formatClock, formatBadge, allowedLinks } from '../format.js';

const root = new URL('../', import.meta.url);
const manifest = JSON.parse(readFileSync(new URL('manifest.json', root), 'utf8'));

function idFromKey(key) {
  const hex = createHash('sha256').update(Buffer.from(key, 'base64')).digest('hex').slice(0, 32);
  return [...hex].map((c) => String.fromCharCode(97 + parseInt(c, 16))).join('');
}

test('key derives the fixed extension ID', () => {
  assert.equal(idFromKey(manifest.key), 'labfclmdkmlcipjlibjnohgahngindoo');
  assert.equal(EXTENSION_ID, 'labfclmdkmlcipjlibjnohgahngindoo');
});

test('manifest basics', () => {
  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.name, 'Locked');
  assert.equal(manifest.version, '0.1.0');
  assert.equal(manifest.incognito, 'spanning');
  assert.deepEqual(manifest.background, { service_worker: 'background.js', type: 'module' });
  assert.deepEqual(manifest.host_permissions, ['<all_urls>']);
  for (const p of ['nativeMessaging', 'webNavigation', 'tabs', 'storage', 'alarms', 'declarativeNetRequest']) {
    assert.ok(manifest.permissions.includes(p), p);
  }
  const cs = manifest.content_scripts[0];
  assert.deepEqual(cs.matches, ['*://*.youtube.com/*']);
  assert.equal(cs.run_at, 'document_start');
});

test('every file the manifest and pages reference exists', () => {
  const files = [
    manifest.background.service_worker,
    manifest.action.default_popup,
    ...Object.values(manifest.icons),
    ...Object.values(manifest.action.default_icon),
    ...manifest.content_scripts.flatMap((c) => c.js),
    'blocked.html',
  ];
  for (const html of ['popup.html', 'blocked.html']) {
    const src = readFileSync(new URL(html, root), 'utf8');
    for (const m of src.matchAll(/(?:src|href)="([^"#:]+)"/g)) files.push(m[1]);
    assert.doesNotMatch(src, /<script(?![^>]*\bsrc=)[^>]*>/, `${html} has an inline script`);
    assert.doesNotMatch(src, /\son[a-z]+=/i, `${html} has an inline event handler`);
  }
  for (const f of files) assert.ok(existsSync(new URL(f, root)), f);
});

test('formatClock', () => {
  assert.equal(formatClock(0), '0:00');
  assert.equal(formatClock(59_001), '1:00');
  assert.equal(formatClock(25 * 60_000), '25:00');
  assert.equal(formatClock(3_723_000), '1:02:03');
  assert.equal(formatClock(-5), '0:00');
});

test('formatBadge', () => {
  assert.equal(formatBadge(0), '');
  assert.equal(formatBadge(1), '1m');
  assert.equal(formatBadge(25 * 60_000), '25m');
  assert.equal(formatBadge(24 * 60_000 + 1), '25m');
  assert.equal(formatBadge(60 * 60_000), '1h00');
  assert.equal(formatBadge(95 * 60_000), '1h35');
  assert.equal(formatBadge(12 * 3600_000), '12h');
  assert.ok(formatBadge(9 * 3600_000 + 59 * 60_000).length <= 4);
});

test('allowedLinks', () => {
  const links = allowedLinks({
    active: true,
    websites: [
      { url: 'claude.ai', scope: 'domain' },
      { url: 'https://docs.python.org/3/', scope: 'page' },
      { url: 'javascript:alert(1)', scope: 'page' },
    ],
    youtubeVideoIds: ['dQw4w9WgXcQ', 'bad'],
  });
  assert.deepEqual(links.map((l) => l.href), [
    'https://claude.ai/',
    'https://docs.python.org/3/',
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  ]);
  assert.deepEqual(allowedLinks({ active: false }), []);
});
