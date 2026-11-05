// Mirrors the behavior of Sources/LockedShared/YouTubeURL.swift (YouTubeURL.videoId(from:)).
// The cases live in youtube-url-cases.json so a Swift test can load the same fixture.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { youtubeVideoId, isValidYouTubeId } from '../allowlist.js';

const cases = JSON.parse(readFileSync(new URL('./youtube-url-cases.json', import.meta.url), 'utf8'));

for (const c of cases) {
  test(`videoId(${JSON.stringify(c.input)}) -> ${c.expected}${c.note ? ` (${c.note})` : ''}`, () => {
    assert.equal(youtubeVideoId(c.input), c.expected);
  });
}

test('isValidId', () => {
  assert.equal(isValidYouTubeId('dQw4w9WgXcQ'), true);
  assert.equal(isValidYouTubeId('a-b_c-d_e-f'), true);
  assert.equal(isValidYouTubeId('dQw4w9WgXc'), false);
  assert.equal(isValidYouTubeId('dQw4w9WgXcQQ'), false);
  assert.equal(isValidYouTubeId('dQw4w9WgXc='), false);
  assert.equal(isValidYouTubeId('dQw4w9WgXcé'), false);
  assert.equal(isValidYouTubeId(null), false);
  assert.equal(isValidYouTubeId(12345678901), false);
});

test('non-string input', () => {
  assert.equal(youtubeVideoId(undefined), null);
  assert.equal(youtubeVideoId(null), null);
  assert.equal(youtubeVideoId(42), null);
});
