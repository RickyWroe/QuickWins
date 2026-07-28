#!/bin/bash
# Assembles dist/QuickWins.app from the SwiftPM executable.
#
# Swift Package Manager produces a bare executable. macOS needs a bundle for the things this
# app depends on: LSUIElement (no Dock tile), a bundle identifier for UserNotifications, and a
# registered app for SMAppService login items.
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/QuickWins.app"

cd "$ROOT"

echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION"
BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/QuickWins"

if [ ! -x "$BINARY" ]; then
    echo "Executable not found at $BINARY" >&2
    exit 1
fi

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/QuickWins"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad hoc)"
# An ad-hoc signature is enough to run locally and to register a login item. Distributing to
# other machines needs a Developer ID signature and notarization; see the README.
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

echo "==> Built $APP"
