import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  isUrlAllowed,
  isSessionActive,
  normalizeState,
  remainingMs,
  parseWebsiteEntry,
  blockedPageUrl,
  EXTENSION_ID,
  SUPPORT_HOSTS,
} from '../allowlist.js';

const NOW = Date.parse('2026-11-05T10:00:00Z');
const LATER = '2026-11-05T11:00:00Z';
const EARLIER = '2026-11-05T09:00:00Z';
const VID = 'dQw4w9WgXcQ';
const OTHER_VID = 'aaaaaaaaaaa';

function session(websites = [], youtubeVideoIds = [], endsAt = LATER) {
  return { type: 'state', active: true, endsAt, websites, youtubeVideoIds };
}

const STATE = session(
  [
    { url: 'https://claude.ai', scope: 'domain' },
    { url: 'www.example.org', scope: 'domain' },
    { url: 'https://docs.python.org/3/docs', scope: 'page' },
    { url: 'https://www.wikipedia.org/wiki/Focus/', scope: 'page' },
    { url: 'news.ycombinator.com', scope: 'page' },
  ],
  [VID],
);

const main = (url, state = STATE, extra = {}) => isUrlAllowed(url, state, { frameType: 'main_frame', now: NOW, ...extra });
const sub = (url, state = STATE, extra = {}) => isUrlAllowed(url, state, { frameType: 'sub_frame', now: NOW, ...extra });

describe('session activity', () => {
  test('no state / inactive state allows everything', () => {
    for (const s of [null, undefined, { active: false }, { type: 'state', active: false }]) {
      assert.equal(isUrlAllowed('https://evil.com/', s, { now: NOW }), true);
      assert.equal(isUrlAllowed('chrome://extensions/', s, { now: NOW }), true);
      assert.equal(isUrlAllowed('https://twitter.com/', s, { frameType: 'sub_frame', now: NOW }), true);
    }
  });

  test('expired endsAt is treated as inactive', () => {
    const expired = session([], [], EARLIER);
    assert.equal(isSessionActive(expired, NOW), false);
    assert.equal(main('https://evil.com/', expired), true);
    assert.equal(main('chrome://extensions', expired), true);
  });

  test('endsAt exactly now is expired (endsAt <= now)', () => {
    const s = session([], [], new Date(NOW).toISOString());
    assert.equal(isSessionActive(s, NOW), false);
    assert.equal(main('https://evil.com/', s), true);
  });

  test('missing or garbage endsAt is treated as inactive', () => {
    assert.equal(isSessionActive({ active: true }, NOW), false);
    assert.equal(isSessionActive({ active: true, endsAt: 'soon' }, NOW), false);
  });

  test('active session with future endsAt blocks unknown sites', () => {
    assert.equal(isSessionActive(STATE, NOW), true);
    assert.equal(main('https://evil.com/'), false);
  });

  test('now can be a Date', () => {
    assert.equal(isSessionActive(STATE, new Date(NOW)), true);
  });

  test('remainingMs', () => {
    assert.equal(remainingMs(STATE, NOW), 3600_000);
    assert.equal(remainingMs({ active: false }, NOW), 0);
  });

  test('normalizeState drops malformed entries', () => {
    const n = normalizeState({
      type: 'state',
      active: true,
      endsAt: LATER,
      websites: [{ url: 'a.com', scope: 'domain' }, { url: 'b.com', scope: 'weird' }, { scope: 'page' }, null],
      youtubeVideoIds: [VID, 5, null],
    });
    assert.deepEqual(n, { active: true, endsAt: LATER, websites: [{ url: 'a.com', scope: 'domain' }], youtubeVideoIds: [VID] });
    assert.deepEqual(normalizeState({ type: 'state', active: false }), { active: false });
    assert.deepEqual(normalizeState(null), { active: false });
    assert.deepEqual(normalizeState({ active: 'true' }), { active: false });
  });
});

describe('rule 1: non-web schemes', () => {
  test('own extension pages are allowed', () => {
    assert.equal(main(`chrome-extension://${EXTENSION_ID}/blocked.html?url=x`), true);
    assert.equal(main(`chrome-extension://${EXTENSION_ID}/popup.html`), true);
    assert.equal(main(blockedPageUrl('https://evil.com/')), true);
    assert.equal(main('chrome-extension://abcdefghijklmnopabcdefghijklmnop/x.html', STATE, { extensionId: 'abcdefghijklmnopabcdefghijklmnop' }), true);
  });

  test('chrome://extensions, settings and flags are blocked', () => {
    for (const u of [
      'chrome://extensions',
      'chrome://extensions/',
      'chrome://extensions/?id=labfclmdkmlcipjlibjnohgahngindoo',
      'chrome://extensions/shortcuts',
      'CHROME://EXTENSIONS/',
      'chrome://settings',
      'chrome://settings/clearBrowserData',
      'chrome://flags/#enable-something',
    ]) {
      assert.equal(main(u), false, u);
      assert.equal(sub(u), false, u);
    }
  });

  test('other non-web schemes are allowed', () => {
    for (const u of ['chrome://newtab/', 'chrome://history/', 'chrome://downloads', 'file:///Users/me/notes.txt', 'about:srcdoc', 'view-source:https://claude.ai/', 'chrome-extension://otherextensionidxxxxxxxxxxxxxxxx/page.html']) {
      assert.equal(main(u), true, u);
    }
  });

  test('about:blank allowed everywhere; data: in sub-frames only', () => {
    assert.equal(sub('about:blank'), true);
    assert.equal(sub('about:blank#x'), true);
    assert.equal(sub('data:text/html,<p>hi</p>'), true);
    assert.equal(main('about:blank'), true);
    assert.equal(main('data:text/html,<p>hi</p>'), false);
  });

  test('unparseable URLs are blocked during a session', () => {
    assert.equal(main('not a url'), false);
    assert.equal(main(''), false);
  });
});

describe('rule 2: domain scope', () => {
  test('exact host, any path, query and fragment', () => {
    assert.equal(main('https://claude.ai/'), true);
    assert.equal(main('https://claude.ai'), true);
    assert.equal(main('https://claude.ai/chat/123?x=1#y'), true);
    assert.equal(main('http://claude.ai/new'), true);
  });

  test('www. handling on both sides', () => {
    assert.equal(main('https://www.claude.ai/'), true);
    assert.equal(main('https://example.org/a'), true); // entry was www.example.org
    assert.equal(main('https://www.example.org/a'), true);
  });

  test('subdomains match', () => {
    assert.equal(main('https://api.claude.ai/x'), true);
    assert.equal(main('https://a.b.claude.ai/'), true);
    assert.equal(main('https://cdn.example.org/'), true);
  });

  test('lookalike domains do not match', () => {
    assert.equal(main('https://evilclaude.ai/'), false);
    assert.equal(main('https://claude.ai.evil.com/'), false);
    assert.equal(main('https://claude.aix/'), false);
    assert.equal(main('https://notexample.org/'), false);
  });

  test('host is case-insensitive, port is ignored', () => {
    assert.equal(main('https://CLAUDE.AI/'), true);
    assert.equal(main('https://claude.ai:8443/'), true);
  });

  test('entry host case and scheme-less entries', () => {
    const s = session([{ url: 'GitHub.com', scope: 'domain' }]);
    assert.equal(main('https://github.com/x', s), true);
    assert.equal(main('https://gist.github.com/x', s), true);
  });

  test('a "www.com" entry does not allow every .com site', () => {
    const s = session([{ url: 'www.com', scope: 'domain' }]);
    assert.equal(main('https://www.com/', s), true);
    assert.equal(main('https://google.com/', s), false);
  });

  test('allows sub-frames too', () => {
    assert.equal(sub('https://claude.ai/embed'), true);
    assert.equal(sub('https://twitter.com/embed'), false);
  });
});

describe('rule 3: page scope', () => {
  test('exact path and descendants', () => {
    assert.equal(main('https://docs.python.org/3/docs'), true);
    assert.equal(main('https://docs.python.org/3/docs/'), true);
    assert.equal(main('https://docs.python.org/3/docs/tutorial/index.html'), true);
  });

  test('sibling path with the same prefix does not match', () => {
    assert.equal(main('https://docs.python.org/3/docsx'), false);
    assert.equal(main('https://docs.python.org/3/doc'), false);
    assert.equal(main('https://docs.python.org/3/'), false);
    assert.equal(main('https://docs.python.org/'), false);
  });

  test('/docs allows /docs/x but not /docsx', () => {
    const s = session([{ url: 'https://site.dev/docs', scope: 'page' }]);
    assert.equal(main('https://site.dev/docs', s), true);
    assert.equal(main('https://site.dev/docs/x', s), true);
    assert.equal(main('https://site.dev/docsx', s), false);
  });

  test('trailing slash on the entry is ignored', () => {
    assert.equal(main('https://wikipedia.org/wiki/Focus'), true);
    assert.equal(main('https://www.wikipedia.org/wiki/Focus/'), true);
    assert.equal(main('https://www.wikipedia.org/wiki/Focus/History'), true);
    assert.equal(main('https://www.wikipedia.org/wiki/Focusing'), false);
  });

  test('query and fragment are ignored', () => {
    assert.equal(main('https://docs.python.org/3/docs?highlight=x#section'), true);
    const s = session([{ url: 'https://site.dev/page?id=1#top', scope: 'page' }]);
    assert.equal(main('https://site.dev/page?id=2', s), true);
    assert.equal(main('https://site.dev/page', s), true);
  });

  test('same host only: no subdomains, www. ignored', () => {
    assert.equal(main('https://www.docs.python.org/3/docs'), true);
    assert.equal(main('https://sub.docs.python.org/3/docs'), false);
    assert.equal(main('https://python.org/3/docs'), false);
  });

  test('root page entry covers the whole host but not subdomains', () => {
    assert.equal(main('https://news.ycombinator.com/'), true);
    assert.equal(main('https://news.ycombinator.com/item?id=1'), true);
    assert.equal(main('https://ycombinator.com/'), false);
    assert.equal(main('https://x.news.ycombinator.com/'), false);
  });

  test('path matching is case-sensitive', () => {
    assert.equal(main('https://docs.python.org/3/Docs'), false);
  });

  test('parseWebsiteEntry', () => {
    assert.deepEqual(parseWebsiteEntry({ url: 'https://www.Example.com/A/b/', scope: 'page' }), { scope: 'page', host: 'example.com', path: '/A/b' });
    assert.deepEqual(parseWebsiteEntry({ url: 'example.com', scope: 'domain' }), { scope: 'domain', host: 'example.com', path: '' });
    assert.equal(parseWebsiteEntry({ url: '', scope: 'domain' }), null);
    assert.equal(parseWebsiteEntry({ url: 'file:///x', scope: 'domain' }), null);
    assert.equal(parseWebsiteEntry({ url: 'a.com', scope: 'other' }), null);
  });
});

describe('rule 4: YouTube', () => {
  test('allowed watch URL, with extra params', () => {
    assert.equal(main(`https://www.youtube.com/watch?v=${VID}`), true);
    assert.equal(main(`https://www.youtube.com/watch?v=${VID}&t=42s&list=PLx&index=2`), true);
    assert.equal(main(`https://www.youtube.com/watch?feature=share&v=${VID}`), true);
    assert.equal(main(`https://youtube.com/watch?v=${VID}`), true);
    assert.equal(main(`https://www.youtube.com/watch?v=${VID}&pp=ygU|x`), true, 'Chrome may leave | unescaped');
  });

  test('disallowed ID is blocked', () => {
    assert.equal(main(`https://www.youtube.com/watch?v=${OTHER_VID}`), false);
    assert.equal(main(`https://www.youtube.com/watch?v=${OTHER_VID}&x=${VID}`), false);
    assert.equal(main(`https://www.youtube.com/watch?v=${OTHER_VID}&v=${VID}`), false, 'first v wins');
  });

  test('other YouTube pages are blocked', () => {
    for (const u of ['https://www.youtube.com/', 'https://www.youtube.com/feed/subscriptions', 'https://www.youtube.com/results?search_query=x', `https://www.youtube.com/shorts/${OTHER_VID}`, 'https://www.youtube.com/@channel']) {
      assert.equal(main(u), false, u);
    }
  });

  test('youtu.be', () => {
    assert.equal(main(`https://youtu.be/${VID}`), true);
    assert.equal(main(`https://youtu.be/${VID}?t=10`), true);
    assert.equal(main(`https://youtu.be/${OTHER_VID}`), false);
  });

  test('embed (main and sub-frame)', () => {
    assert.equal(main(`https://www.youtube.com/embed/${VID}`), true);
    assert.equal(sub(`https://www.youtube.com/embed/${VID}?autoplay=1`), true);
    assert.equal(sub(`https://youtube.com/embed/${VID}`), true);
    assert.equal(sub(`https://www.youtube.com/embed/${OTHER_VID}`), false);
  });

  test('shorts and live', () => {
    assert.equal(main(`https://www.youtube.com/shorts/${VID}`), true);
    assert.equal(main(`https://www.youtube.com/live/${VID}`), true);
  });

  test('m.youtube.com', () => {
    assert.equal(main(`https://m.youtube.com/watch?v=${VID}`), true);
    assert.equal(main(`https://m.youtube.com/watch?v=${OTHER_VID}`), false);
    assert.equal(main('https://m.youtube.com/'), false);
  });

  test('hosts outside rule 4 are not unlocked by an ID', () => {
    assert.equal(main(`https://music.youtube.com/watch?v=${VID}`), false);
    assert.equal(main(`https://www.youtube-nocookie.com/embed/${VID}`), false);
    assert.equal(main(`https://www.youtu.be/${VID}`), false);
    assert.equal(main(`https://evilyoutube.com/watch?v=${VID}`), false);
    assert.equal(main(`https://youtube.com.evil.com/watch?v=${VID}`), false);
  });

  test('IDs are case-sensitive', () => {
    assert.equal(main(`https://www.youtube.com/watch?v=${VID.toLowerCase()}`), false);
  });

  test('YouTube as a website entry allows all of it', () => {
    const s = session([{ url: 'youtube.com', scope: 'domain' }]);
    assert.equal(main('https://www.youtube.com/', s), true);
    assert.equal(main(`https://www.youtube.com/watch?v=${OTHER_VID}`, s), true);
  });
});

describe('rule 5: support hosts', () => {
  test('all support hosts are allowed in main and sub-frames', () => {
    const empty = session();
    for (const h of SUPPORT_HOSTS) {
      assert.equal(main(`https://${h}/some/path?x=1`, empty), true, h);
      assert.equal(sub(`https://${h}/`, empty), true, h);
    }
  });

  test('support hosts are exact, not suffixes', () => {
    const empty = session();
    assert.equal(main('https://google.com/', empty), false);
    assert.equal(main('https://mail.google.com/', empty), false);
    assert.equal(main('https://evil-accounts.google.com.evil.com/', empty), false);
    assert.equal(main('https://gstatic.com/', empty), false);
    assert.equal(main('https://openai.com/', empty), false);
    assert.equal(main('https://cloudflare.com/', empty), false);
  });
});

describe('rule 6: sub-resources are never blocked', () => {
  test('non-frame types are allowed even for blocked URLs', () => {
    for (const frameType of ['script', 'image', 'xmlhttprequest', 'media', 'stylesheet', 'font', 'other']) {
      assert.equal(isUrlAllowed('https://evil.com/x.js', STATE, { frameType, now: NOW }), true, frameType);
    }
  });

  test('frameType defaults to main_frame', () => {
    assert.equal(isUrlAllowed('https://evil.com/', STATE, { now: NOW }), false);
  });
});

test('blockedPageUrl encodes the URL', () => {
  const u = blockedPageUrl('https://evil.com/a?b=c&d=e#f');
  assert.equal(u, `chrome-extension://${EXTENSION_ID}/blocked.html?url=https%3A%2F%2Fevil.com%2Fa%3Fb%3Dc%26d%3De%23f`);
  assert.equal(new URL(u).searchParams.get('url'), 'https://evil.com/a?b=c&d=e#f');
});
