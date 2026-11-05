# Locked: Chrome extension

The Chrome half of Locked. During a focus session it blocks every website that isn't on the
session's allowlist, allows only the listed YouTube videos, and hides YouTube's distractions.
It gets the session from the Locked app through the native messaging host `app.locked.bridge`.

Extension ID: `labfclmdkmlcipjlibjnohgahngindoo`. It's fixed by the `key` in `manifest.json`, and
the native host manifest only accepts this ID.

## Install (once)

1. Launch Locked.app once. It copies this folder to
   `~/Library/Application Support/Locked/ChromeExtension` and installs the native host manifest.
2. In Chrome, open `chrome://extensions` and turn on **Developer mode** (top right).
3. Click **Load unpacked**. Press <kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>G</kbd> in the file dialog, paste
   `~/Library/Application Support/Locked/ChromeExtension` and choose that folder.
4. Open the extension's **Details** and turn on **Allow in Incognito**. Without this, incognito
   windows aren't filtered.
5. Pin the extension if you like. The badge shows the time left in the session (e.g. `25m`), and
   the popup shows whether the extension is connected to the app.

After Locked updates the folder, click the reload icon on the extension's card in `chrome://extensions`.

## How it works

| File | Role |
|---|---|
| `manifest.json` | MV3 manifest (module service worker, `incognito: spanning`, YouTube content script) |
| `background.js` | Native messaging client, enforcement, badge |
| `allowlist.js` | The allowlist rules from SPEC.md (pure module, no `chrome.*`) |
| `dnr.js` | Converts the allowlist into declarativeNetRequest rules for sub-frames (pure module) |
| `format.js`, `ui.js` | Shared helpers for the popup and the blocked page |
| `blocked.html/.js/.css` | Page shown in place of a blocked site |
| `popup.html/.js/.css` | Toolbar popup |
| `youtube.js` | YouTube cleanup content script |
| `tests/` | Node tests. Chrome ignores this folder. |

- **Bridge:** `connectNative('app.locked.bridge')`, then `hello` with the manifest version, then a
  `ping` every 20s. On disconnect it reconnects with backoff (1s, 2s, 4s, up to 30s). A 30s
  `chrome.alarms` alarm wakes the worker as a backstop. The last state is cached in
  `chrome.storage.session`, so a restarted worker keeps enforcing while it reconnects.
- **Disconnected or no session:** everything is allowed. The app handles the fail-closed side by
  hiding Chrome when the bridge heartbeat is stale.
- **Main frames:** `webNavigation.onBeforeNavigate`, `onCommitted` and `onHistoryStateUpdated` (for
  single-page-app navigations like YouTube), plus `tabs.onUpdated`. A blocked tab is sent to
  `blocked.html?url=…`. All open tabs are re-checked whenever an active state arrives and on every alarm.
- **Sub-frames:** handled by declarativeNetRequest session rules. They block all `sub_frame`
  requests and allow the ones that match the allowlist. The browser enforces these before the
  request goes out, and they keep working while the worker sleeps. `tests/dnr.test.mjs` checks
  that the rules agree with `allowlist.js`.
- **chrome://extensions, settings, flags:** redirected away through `tabs.onUpdated`. This works in
  current Chrome, but Chrome doesn't guarantee it.
- **YouTube:** on allowed videos the content script hides recommendations, comments, end-screen
  cards, the home feed, Shorts, the left guide and the autoplay toggle, and turns autoplay off.
  If YouTube as a whole is allowlisted as a website, it leaves YouTube alone.

## Tests

```sh
node --test tests/*.test.mjs
```

The tests need Node 18 or later. `tests/youtube-url-cases.json` lists the YouTube parsing cases that
`allowlist.js` must handle the same way as `Sources/LockedShared/YouTubeURL.swift`. A Swift test can
load the same file.

## Known gaps

- Incognito windows aren't filtered unless **Allow in Incognito** is on. Chrome profiles without
  this extension aren't filtered at all.
- An extension in `spanning` mode can't show its own pages in incognito tabs. A blocked incognito
  tab gets a Chrome error page instead of `blocked.html`. That still blocks the site.
- Blocking sub-frames can break third-party widgets on allowed sites (captchas other than
  Cloudflare's, payment iframes, embeds). Add the widget's domain to the allowlist if you need it.
- Other browsers, safe mode, another admin account, or deleting `session.json` can all get around
  Locked. It's a self-discipline tool, not tamper-proof.
