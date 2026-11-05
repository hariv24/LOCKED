# Locked

A self-built, Cold-Turkey-style focus blocker for macOS 14+.

Start a timed session, and until the timer ends you can only use what you allowed beforehand:
specific **apps** (VS Code, Notes, ChatGPT, Claude…), **websites** (one page or a whole domain),
specific **YouTube videos** (recommendations, comments and autoplay hidden), and **PDFs**
(opened in Locked's built-in viewer). Every other app gets hidden the moment it comes to the front.

Locked never sees your passwords. Websites open in your normal Chrome with your normal logins.
A small Chrome extension only decides which URLs are allowed.

## How it works

```
 Locked.app (SwiftUI)        writes  ~/Library/Application Support/Locked/session.json
   ├─ AppBlocker             hides every non-allowed app (NSWorkspace notifications + 1s sweep)
   ├─ PDF viewer             PDFKit, so Preview isn't needed
   ├─ Timer pill             floating countdown on top of everything
   └─ LaunchAgent ──────────▶ LockedWatchdog: relaunches Locked if it's force-quit
 Chrome ── extension ◀─native messaging─▶ LockedBridge (reads session.json, writes a heartbeat)
```

If the extension is disabled or disconnected, the heartbeat stops and Locked hides Chrome entirely.
See [SPEC.md](SPEC.md) for the full contract.

## Build & install (on a Mac)

Requirements: macOS 14+, Xcode 15 or 16 (or just the Command Line Tools with Swift 5.9+), Google Chrome.

```bash
./scripts/install.sh          # builds build/Locked.app and copies it to /Applications
```

Or build without installing: `./scripts/build-app.sh` produces `build/Locked.app`.

Run the tests: `swift test`

## First-time setup

1. Open **Locked** from /Applications. Allow notifications when asked.
2. Install the Chrome extension (once):
   Chrome → `chrome://extensions` → turn on **Developer mode** → **Load unpacked** →
   choose `~/Library/Application Support/Locked/ChromeExtension` (Locked's "Show extension folder" button opens it).
   Then open the extension's **Details** and turn on **Allow in Incognito**.
3. Locked's setup screen should now say the Chrome extension is **connected**.

## Using it

1. Pick allowed apps, paste websites / YouTube links, and add PDFs. "Add AI sites" adds ChatGPT, Claude and Gemini.
2. Choose a duration and press **Start**. Save the setup as a preset if you'll reuse it.
3. Emergency exit: type the 40-character phrase shown on screen, wait 60 seconds, confirm. Early exits are logged in History.

## Known limits (honest)

This is a self-discipline tool, not tamper-proof:
- Chrome profiles without the extension, or Incognito when "Allow in Incognito" is off, aren't filtered.
  Locked can only tell whether *some* extension instance is connected.
- Rebooting into Safe Mode, another admin account, or deleting `session.json` / the LaunchAgent from a terminal can get around it.
- Only Chrome is supported as the browser. Every other browser gets hidden like any other app.
- Sub-frames (embeds) from non-allowed domains are blocked on allowed sites, which can break things like reCAPTCHA.
  Add the widget's domain to the allowlist if needed.
- The app is ad-hoc signed, so on first open you may need right-click → Open.
