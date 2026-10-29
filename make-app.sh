#!/bin/sh
# Usage: ./make-app.sh
set -eu

VERSION=1.0.2

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
echo "Building Airwave $VERSION"

swift build -c release

BIN_DIR=$(swift build -c release --show-bin-path)
APP=dist/Airwave.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Airwave" "$APP/Contents/MacOS/Airwave"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Airwave</string>
  <key>CFBundleIdentifier</key><string>com.example.airwave</string>
  <key>CFBundleExecutable</key><string>Airwave</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP — drag it to /Applications."
