# Airwave

A tiny native macOS (SwiftUI) player for audio from YouTube livestreams and other websites.

## Features
- Paste a link → audio plays (YouTube live, SoundCloud, Twitch, radio streams, direct mp3/aac/m3u8…)
- **Paste** button puts the clipboard link straight into the box
- Shows up in macOS **Now Playing** (Control Center, media keys, AirPods controls)
- **Hotstart**: auto-plays the last stream or a chosen favorite at launch
- **Favorites** list (double-click to play; rename/delete via "…"; drag the handle to reorder)
- Errors pop up as alerts; a failed link leaves the previous track playing
- **Preferences**: ⌘, or the ⚙ button in the window's top-right corner

## Requirements
- macOS 14+, Xcode 15+ (or Command Line Tools)
- `./make-app.sh` downloads and bundles `yt-dlp` inside the app automatically. To update it: delete `vendor/yt-dlp` and rerun the script.
- For `swift run`, install it once: `brew install yt-dlp`

## Run
```sh
swift run                                  # quick try (yt-dlp backend)
AIRWAVE_BACKEND=youtubekit swift run       # quick try (YouTubeKit backend)
./make-app.sh                              # builds build/Airwave.app with bundled yt-dlp
./make-app.sh --backend youtubekit         # smaller app, YouTube + direct links only
```

## Backends
| | yt-dlp (default) | YouTubeKit |
|---|---|---|
| Sites | YouTube + 1000s of others | YouTube only (+ direct audio links) |
| App size | ~35 MB | ~1 MB |
| Updates | replace `vendor/yt-dlp` | update the Swift package |
Or open `Package.swift` in Xcode and press ⌘R.

## Notes
- The app is not sandboxed because it launches `yt-dlp`; this is fine for personal use / outside the Mac App Store.
- Closing the last window quits Airwave, even while audio is playing.
- Thumbnails come from the video/stream, else the page's preview image, else its site icon, and are saved with favorites.
- Live streams resume at the live edge after a pause.
