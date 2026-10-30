#!/bin/sh
# Usage: ./smoke-test.sh
#
# Verifies that Airwave builds and that its Foundation-only logic behaves as
# expected. Used as the project's test safety net because XCTest and Swift
# Testing require a full Xcode install, which is not assumed here.
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

echo "==> Building release"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/Airwave"
[ -x "$BIN" ] || { echo "FAIL: release binary not found at $BIN"; exit 1; }
echo "ok: release binary at $BIN"

echo "==> Running pure-logic smoke checks"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -swift-version 5 \
  Tests/Smoke/main.swift \
  Sources/Airwave/Services/Prefs.swift \
  Sources/Airwave/Services/Favorite.swift \
  Sources/Airwave/Services/FavoritesIO.swift \
  -o "$TMP/smoke"
"$TMP/smoke"

echo "Smoke test complete."
