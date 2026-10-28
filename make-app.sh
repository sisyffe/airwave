#!/bin/sh
# Builds Airwave.app
# Usage: ./make-app.sh [--backend ytdlp|youtubekit]
#   ytdlp      (default) bundles the yt-dlp binary (~35 MB). Works with YouTube + 1000s of sites.
#   youtubekit Swift library compiled in (~1 MB). YouTube + direct audio links only.
set -e
BACKEND=ytdlp
while [ $# -gt 0 ]; do
  case "$1" in
    --backend) BACKEND="$2"; shift 2 ;;
    --backend=*) BACKEND="${1#*=}"; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done
case "$BACKEND" in ytdlp|yt-dlp) BACKEND=ytdlp ;; youtubekit) ;; *) echo "Backend must be ytdlp or youtubekit"; exit 1 ;; esac
echo "Building Airwave with backend: $BACKEND"

# Clean so switching backends always recompiles with the right flags
rm -rf .build/release
AIRWAVE_BACKEND=$BACKEND swift build -c release

APP=build/Airwave.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Airwave "$APP/Contents/MacOS/Airwave"

if [ "$BACKEND" = ytdlp ]; then
  mkdir -p vendor
  [ -f vendor/yt-dlp ] || curl -L -o vendor/yt-dlp https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos
  chmod +x vendor/yt-dlp
  cp vendor/yt-dlp "$APP/Contents/Resources/yt-dlp"
  codesign --force --sign - "$APP/Contents/Resources/yt-dlp"
fi

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
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1.0.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP ($BACKEND) — drag it to /Applications."
