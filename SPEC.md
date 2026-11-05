# Locked: Architecture & Contract

Locked is a self-built focus blocker for macOS 14+, modeled on how Cold Turkey works.
During a timed session only allowlisted apps, websites, YouTube videos and PDFs are usable.

This file is the **source of truth**. Every component must follow it exactly.
If something here is wrong or missing, flag it. Do not silently diverge.

## Components

| Component | Path | Language | Role |
|---|---|---|---|
| LockedShared | `Sources/LockedShared/` | Swift (Foundation only, must compile on Linux too) | Models, file paths, JSON store. Shared by all Swift targets. |
| Locked (app) | `Sources/Locked/` | Swift, SwiftUI + AppKit | UI, session manager, app blocker, PDF viewer, installers |
| LockedBridge | `Sources/LockedBridge/` | Swift (Foundation only) | Chrome native-messaging host. Chrome launches it. |
| LockedWatchdog | `Sources/LockedWatchdog/` | Swift (Foundation only) | Run by a LaunchAgent during a session; relaunches Locked if it's killed |
| Chrome extension | `ChromeExtension/` | JS, Manifest V3 | Blocks non-allowlisted URLs in Chrome; YouTube cleanup |
| Packaging | `Package.swift`, `scripts/build-app.sh`, `Resources/Info.plist` | | Builds `build/Locked.app` with no Xcode project needed |

## Identifiers (fixed, do not change)

- App bundle ID: `app.locked.Locked`
- Native messaging host name: `app.locked.bridge`
- Chrome extension ID: `labfclmdkmlcipjlibjnohgahngindoo` (derived from the `key` in `ChromeExtension/manifest.json`)
- LaunchAgent label: `app.locked.watchdog`
- Chrome bundle ID: `com.google.Chrome`

## Files on disk

Base dir: `~/Library/Application Support/Locked/` (`LockedPaths.baseDir`)

| File | Writer | Readers | Content |
|---|---|---|---|
| `session.json` | App | Bridge, Watchdog, App | `SessionState`. Present while a session is active; deleted when it ends. |
| `presets.json` | App | App | `[Preset]` |
| `history.json` | App | App | `[HistoryEntry]` |
| `bridge-heartbeat.json` | Bridge | App | `BridgeHeartbeat`. Rewritten every 2s while Chrome's extension is connected. |
| `ChromeExtension/` | App (copied from the app bundle's Resources on launch) | Chrome | User does "Load unpacked" from this folder once. |

Other locations:
- Native host manifest (App installs on every launch): `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/app.locked.bridge.json`
  ```json
  { "name": "app.locked.bridge", "description": "Locked bridge", "path": "<abs path to Locked.app/Contents/MacOS/LockedBridge>",
    "type": "stdio", "allowed_origins": ["chrome-extension://labfclmdkmlcipjlibjnohgahngindoo/"] }
  ```
- LaunchAgent (App installs at session start, removes at session end): `~/Library/LaunchAgents/app.locked.watchdog.plist`
  - ProgramArguments: `[<Locked.app>/Contents/MacOS/LockedWatchdog, "--app", <abs path to Locked.app>]`
  - `RunAtLoad` true, `KeepAlive` = `{ SuccessfulExit: false }` (a clean exit 0 means "session over, stop me")
  - Loaded with `launchctl bootstrap gui/<uid> <plist>`, removed with `launchctl bootout gui/<uid>/app.locked.watchdog`

All JSON uses ISO-8601 dates (`JSONEncoder.DateEncodingStrategy.iso8601`) and pretty-printed sorted keys.
Writes are atomic (`Data.write(to:options:.atomic)`). Use `LockedStore` from LockedShared. Don't hand-roll this.

## Data model (implemented in LockedShared; see the code there)

```
WebsiteScope: "page" | "domain"
WebsiteEntry { id: UUID, url: String, scope: WebsiteScope }
AllowedApp  { bundleId: String, name: String, path: String? }
PDFEntry    { id: UUID, path: String }       // absolute file path
YouTubeEntry{ id: UUID, videoId: String, title: String? }
Allowlist   { apps: [AllowedApp], websites: [WebsiteEntry], youtube: [YouTubeEntry], pdfs: [PDFEntry] }
Preset      { id: UUID, name: String, allowlist: Allowlist, durationMinutes: Int }
SessionState{ version: 1, sessionId: UUID, startedAt: Date, endsAt: Date, allowlist: Allowlist }
HistoryEntry{ id: UUID, startedAt: Date, plannedEndAt: Date, endedAt: Date, outcome: "completed" | "exitedEarly" }
BridgeHeartbeat { lastSeen: Date, extensionVersion: String? }
```

`YouTubeURL.videoId(from:)` parses watch/youtu.be/embed/shorts/live URLs into an 11-char ID. The app uses it when the user pastes a link.

## Native messaging protocol (Bridge ⇄ Extension)

Framing (Chrome standard): 4-byte **little-endian** UInt32 length, then UTF-8 JSON. Max 1 MB from host.

Extension → Bridge:
- `{"type":"hello","version":"<manifest version>"}` sent right after `connectNative`
- `{"type":"ping"}` every 20s (keepalive; bridge just refreshes the heartbeat)

Bridge → Extension:
- `{"type":"state","active":true,"endsAt":"<ISO>","websites":[{"url":..,"scope":"page"|"domain"}],"youtubeVideoIds":["..."]}`
- `{"type":"state","active":false}` when there's no session or it has expired (`endsAt <= now`)
- Bridge sends state right after `hello`, then again whenever `session.json` changes (it polls the file's mtime/contents every 1s) and when the session expires.

Bridge lifecycle: it reads stdin on a background thread and exits(0) on EOF (Chrome closes the pipe when the extension disconnects). While connected it writes `bridge-heartbeat.json` every 2s. Log only to stderr. stdout is the protocol channel.

## URL allowlist semantics (implemented ONLY in the extension: `ChromeExtension/allowlist.js`)

A main-frame or sub-frame navigation URL is allowed during an active session iff any rule matches:
1. Non-web schemes: `chrome-extension://<own id>/*` is allowed. Everything else non-http(s) is allowed EXCEPT `chrome://extensions*`, `chrome://settings*` and `chrome://flags*`, which are blocked (to make it harder to disable the extension). `about:blank` is allowed in any frame (login pop-ups); `data:` in sub-frames only.
2. Website `domain` scope: the URL host equals the entry's host or is a subdomain of it (strip a leading `www.` from both before comparing). Any path.
3. Website `page` scope: same host (ignoring `www.`), and the URL path equals the entry path or starts with entry path + `/`, ignoring a trailing slash. Query and fragment are ignored.
4. YouTube: host is `youtube.com`, `www.youtube.com`, `m.youtube.com` or `youtu.be`, and the video ID (parsed like `YouTubeURL.videoId`) is in `youtubeVideoIds`. Also allowed for YouTube playback/login: `youtube.com/embed/<allowed id>`, and the support hosts in rule 5.
5. Always-allowed support hosts (login and asset domains, so allowed sites keep working): `accounts.google.com`, `accounts.youtube.com`, `ssl.gstatic.com`, `www.gstatic.com`, `auth.openai.com`, `auth0.openai.com`, `appleid.apple.com`, `challenges.cloudflare.com`, `consent.youtube.com`, `consent.google.com`. Main-frame navigations to these are allowed.
6. Sub-resources (scripts, images, XHR, media) are NEVER blocked. Only main_frame and sub_frame navigations are.

Blocked main-frame navigations redirect to `chrome-extension://labfclmdkmlcipjlibjnohgahngindoo/blocked.html?url=<encoded>`.
If the bridge is disconnected or there's no active session, the extension allows everything. The app enforces the fail-closed side (see below).

## App-side enforcement rules

- During a session, every running regular app (`activationPolicy == .regular`) not on the allowlist gets `hide()`d.
  This runs on `NSWorkspace.didActivateApplicationNotification`, on `didLaunchApplicationNotification`, at session start for already-running apps, and on a 1s safety timer.
  After hiding, Locked activates the most recently used allowed app, or itself.
- Always allowed (never hidden): Locked itself, `com.apple.finder` (but Finder IS hidden; it just isn't counted as a violation), `com.apple.loginwindow`, `com.apple.dock`, `com.apple.systemuiserver`, `com.apple.controlcenter`, `com.apple.notificationcenterui`, `com.apple.Spotlight`, `com.apple.SecurityAgent`, `com.apple.UserNotificationCenter`, `com.apple.universalAccessAuthWarn`, `com.apple.coreservices.uiagent`.
- Chrome (`com.google.Chrome`) is allowed only if the allowlist has ≥1 website or YouTube entry AND `bridge-heartbeat.json`'s `lastSeen` is < 6s old. Otherwise it's hidden like any other app.
- PDFs open in Locked's built-in PDFKit viewer, never in Preview.
- Cmd+Q / quit is refused during a session (`applicationShouldTerminate` → `.terminateCancel`).
- Logout / shutdown / restart (`NSWorkspace.willPowerOffNotification`): quitting is allowed for 120s. If a session is active, the watchdog job is booted out (`launchctl bootout gui/<uid>/app.locked.watchdog`) so it can't relaunch Locked mid-logout, but `session.json` and the plist stay on disk (`RunAtLoad` restarts it at the next login and the session resumes). If the logout is cancelled, the 120s flag reset refuses quit again and re-installs the LaunchAgent if the session is still active.
- Emergency exit: show a random 40-char phrase (letters and digits in groups of 5, displayed as non-selectable text). The user types it exactly, then a 60s countdown runs, then a confirm button ends the session. This is logged as `exitedEarly`.
- Session end (timer or emergency): delete `session.json`, boot out and delete the LaunchAgent plist, append a `HistoryEntry`, post a notification and play a sound.
- On launch: if `session.json` exists and `endsAt > now`, resume the session immediately (re-install the LaunchAgent if it's missing). If it exists but has expired, finish it as `completed`.

## Watchdog rules

`LockedWatchdog --app <path>` loop every 2s:
- If `session.json` is missing or expired → `exit(0)`.
- Else, if no process named `Locked` belonging to that bundle is running (check with `/usr/bin/pgrep -f "<path>/Contents/MacOS/Locked$"`, or equivalent) → run `/usr/bin/open -a <path>`.

## Known gaps (document in README; don't try to solve in v1)

Incognito windows and Chrome profiles without the extension aren't filtered (unless the user enables "Allow in Incognito"). Rebooting into safe mode, using another admin account, or deleting `session.json` from a terminal before Terminal gets hidden can all bypass it. This is a self-discipline tool, not tamper-proof.
