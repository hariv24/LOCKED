#!/usr/bin/env bash
# Builds build/Locked.app (no Xcode project needed). Run on macOS 14+ with Xcode or the
# Command Line Tools installed.
#
#   scripts/build-app.sh            # release build for the host architecture
#   scripts/build-app.sh --arm64    # force an arm64 build
#   scripts/build-app.sh --arch x86_64
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [--arm64 | --arch <arch>]

Builds Locked, LockedBridge and LockedWatchdog in release mode and assembles
build/Locked.app (ad-hoc signed). Default architecture: the host's.
EOF
}

ARCH_FLAGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arm64) ARCH_FLAGS=(--arch arm64); shift ;;
        --arch)
            [[ $# -ge 2 ]] || { echo "error: --arch needs a value" >&2; exit 2; }
            ARCH_FLAGS=(--arch "$2"); shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: Locked.app can only be built on macOS (the app target uses SwiftUI/AppKit)." >&2
    exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/Locked.app"
PRODUCTS=(Locked LockedBridge LockedWatchdog)

# ${ARCH_FLAGS[@]+...} keeps `set -u` happy with an empty array on bash 3.2 (macOS /bin/bash).
for product in "${PRODUCTS[@]}"; do
    echo "==> swift build -c release --product $product ${ARCH_FLAGS[*]+${ARCH_FLAGS[*]}}"
    swift build -c release --product "$product" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
done

BIN="$(swift build -c release --show-bin-path ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"})"
echo "==> binaries in $BIN"
for product in "${PRODUCTS[@]}"; do
    [[ -x "$BIN/$product" ]] || { echo "error: missing built binary $BIN/$product" >&2; exit 1; }
done
[[ -d "$ROOT/ChromeExtension" ]] || { echo "error: ChromeExtension/ not found" >&2; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for product in "${PRODUCTS[@]}"; do
    cp "$BIN/$product" "$APP/Contents/MacOS/$product"
    chmod 755 "$APP/Contents/MacOS/$product"
done
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# The extension folder the app copies to ~/Library/Application Support/Locked/ChromeExtension.
# Dev-only files (tests, node_modules, dotfiles) are left out.
EXT="$APP/Contents/Resources/ChromeExtension"
cp -R "$ROOT/ChromeExtension" "$EXT"
rm -rf "$EXT/node_modules" "$EXT/tests" "$EXT/package.json" "$EXT/package-lock.json"
find "$EXT" -name '.*' -prune -exec rm -rf {} +
[[ -f "$EXT/manifest.json" ]] || echo "warning: ChromeExtension/manifest.json is missing" >&2

plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> ad-hoc signing"
# Sign the helpers with stable identifiers first, then the bundle (main executable + resource
# seal, which records the helpers' signatures). No --deep here: it would re-sign the helpers and
# replace their identifiers with the file names.
codesign --force --sign - --identifier app.locked.bridge "$APP/Contents/MacOS/LockedBridge"
codesign --force --sign - --identifier app.locked.watchdog "$APP/Contents/MacOS/LockedWatchdog"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

cat <<EOF

Built $APP

Next steps:
  1. Install it:        scripts/install.sh   (or: cp -R build/Locked.app /Applications/)
  2. Launch Locked once from /Applications. On launch it installs the Chrome native
     messaging host manifest and copies the extension to
     ~/Library/Application Support/Locked/ChromeExtension
  3. In Chrome: chrome://extensions -> enable Developer mode -> "Load unpacked" ->
     pick ~/Library/Application Support/Locked/ChromeExtension
     (Optional: "Allow in Incognito" so incognito windows are filtered too.)
  4. Restart Chrome so it picks up the native messaging host, then start a session.

Note: the app is ad-hoc signed. If Gatekeeper complains, right-click -> Open the first time.
EOF
