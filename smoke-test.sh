#!/bin/sh
# Usage: ./smoke-test.sh
#
# Verifies that Airwave builds, is formatted, and that its Foundation-only logic
# behaves as expected. Used as the project's test safety net because XCTest and
# Swift Testing require a full Xcode install, which is not assumed here.
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

echo "==> Building release"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/Airwave"
[ -x "$BIN" ] || { echo "FAIL: release binary not found at $BIN"; exit 1; }
echo "ok: release binary at $BIN"

echo "==> Checking formatting"
swift format lint --recursive Sources
echo "ok: Sources is formatted"

echo "==> Running pure-logic smoke checks"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -swift-version 5 \
  Tests/Smoke/main.swift \
  Sources/Airwave/Services/Prefs.swift \
  Sources/Airwave/Services/Favorites.swift \
  Sources/Airwave/Services/FavoritesIO.swift \
  Sources/Airwave/Services/Recents.swift \
  Sources/Airwave/Services/ThumbnailCache.swift \
  Sources/Airwave/Services/ICYMetadata.swift \
  Sources/Airwave/Services/PlaybackGeneration.swift \
  Sources/Airwave/Utilities/URLValidation.swift \
  Sources/Airwave/Utilities/UserDefaultsJSON.swift \
  Sources/Airwave/Utilities/NSImage+Downsizing.swift \
  Sources/Airwave/Utilities/AppInfo.swift \
  -o "$TMP/smoke"
"$TMP/smoke"

echo "Smoke test complete."
