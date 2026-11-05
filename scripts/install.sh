#!/usr/bin/env bash
# Builds Locked.app and installs it to /Applications/Locked.app, replacing any old copy.
# Refuses to run while a Locked session is active.
#
#   scripts/install.sh [--arm64 | --arch <arch>]   (flags are passed to build-app.sh)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/build/Locked.app"
DEST="/Applications/Locked.app"
SESSION_FILE="$HOME/Library/Application Support/Locked/session.json"

check_no_session() {
    if [[ -e "$SESSION_FILE" ]]; then
        # An expired session that the app never finished (e.g. it was deleted) doesn't count; the
        # app finishes it as "completed" on its next launch. Both sides are UTC ISO-8601 with
        # whole seconds ("2026-11-05T10:00:00Z"), so a string comparison orders them correctly.
        local ends now
        ends="$(plutil -extract endsAt raw -o - "$SESSION_FILE" 2>/dev/null || true)"
        now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        if [[ "$ends" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ && ! "$ends" > "$now" ]]; then
            echo "note: found an expired session file (ended $ends); continuing." >&2
            return 0
        fi
        echo "warning: a Locked session appears to be active ($SESSION_FILE exists)." >&2
        echo "Not replacing the app mid-session. Wait for the session to end, then run this again." >&2
        exit 1
    fi
}

check_no_session
"$ROOT/scripts/build-app.sh" "$@"
check_no_session  # a session may have started while we were building

if pgrep -x Locked >/dev/null 2>&1; then
    echo "==> quitting the running Locked"
    osascript -e 'tell application id "app.locked.Locked" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
        pgrep -x Locked >/dev/null 2>&1 || break
        sleep 0.5
    done
    if pgrep -x Locked >/dev/null 2>&1; then
        echo "error: Locked is still running; quit it and run this again." >&2
        exit 1
    fi
fi

echo "==> installing to $DEST"
if [[ -e "$DEST" ]]; then
    rm -rf "$DEST" 2>/dev/null || sudo rm -rf "$DEST"
fi
ditto "$SRC" "$DEST" 2>/dev/null || sudo ditto "$SRC" "$DEST"

cat <<EOF

Installed $DEST

Next steps:
  1. open "$DEST"   (it registers the Chrome native messaging host on every launch)
  2. If you haven't yet: chrome://extensions -> Developer mode -> "Load unpacked" ->
     ~/Library/Application Support/Locked/ChromeExtension, then restart Chrome.
EOF
