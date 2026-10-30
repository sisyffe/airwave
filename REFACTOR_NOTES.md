# Refactor Notes

## Summary

Airwave is a small SwiftUI macOS app (~1,700 lines). This refactor was
structure, naming, documentation and a handful of approved bug fixes. No
features were added and the public behavior, CLI/build entry points and the
favorites JSON format are unchanged.

Organizing principle: **by layer** (`Views` / `Components` / `Services` /
`Utilities`), applied consistently. This matches the layout the project already
used.

What changed:

- **Structure**
  - `TitlebarAccessory.swift` (a service + a view + an AppKit bridge) was split
    into `Services/ConnectionMonitor.swift`, `Components/TitlebarButtons.swift`
    and `Components/TitlebarAccessoryInstaller.swift`.
  - `Views/PreferencesView.swift` (4 view types) was split into
    `Views/Preferences/`, one file per tab plus the editor.
  - The `NSImage.downsized` extension moved out of `StreamResolver.swift` into
    `Utilities/NSImage+Downsizing.swift`.
  - `Thumb.swift` was renamed to `Thumbnail.swift`; the type `Thumb` is now
    `Thumbnail`.
  - New shared helpers: `Utilities/UserDefaultsJSON.swift` and
    `Utilities/AppInfo.swift`.
  - Stray `.DS_Store` files were removed (they were untracked).
- **Duplication**
  - The JSON-encode-to-`UserDefaults` logic in `FavoritesStore` and
    `RecentsStore` now goes through `UserDefaultsJSON`.
  - Thumbnails for favorites and recents are downscaled by one shared
    `ThumbnailCache`, so both store identical bytes.
- **Naming** — short identifiers (`fav`, `gen`, `conn`, `req`, `meta`, `opts`,
  `img`, `yt`, `s`, `q`, ...) were spelled out; one name per concept is used
  everywhere. Magic numbers/strings (thumbnail sizes, timeouts, user agents,
  app name/version, HTML cap) became named constants.
- **Functions** — `AudioPlayer.play` was split into `beginLoading`, `start`,
  `makePlayerItem` and `refreshArtwork`; `ConnectionMonitor` and the
  preferences bodies were clarified.
- **Formatting** — a `.swift-format` config matching the project's 4-space
  convention was added and applied with the bundled `swift format`.

## Old → New File Map

| Old | New | Kind |
| --- | --- | --- |
| `Components/TitlebarAccessory.swift` | `Services/ConnectionMonitor.swift` | split |
| | `Components/TitlebarButtons.swift` | split |
| | `Components/TitlebarAccessoryInstaller.swift` | split |
| `Views/PreferencesView.swift` | `Views/Preferences/PreferencesView.swift` | split |
| | `Views/Preferences/GeneralPreferences.swift` | split |
| | `Views/Preferences/RecentsPreferences.swift` | split |
| | `Views/Preferences/FavoritesPreferences.swift` | split |
| | `Views/Preferences/FavoriteEditor.swift` | split |
| `Components/Thumb.swift` | `Components/Thumbnail.swift` | renamed |
| (extension in `Services/StreamResolver.swift`) | `Utilities/NSImage+Downsizing.swift` | moved |
| — | `Utilities/UserDefaultsJSON.swift` | new |
| — | `Utilities/AppInfo.swift` | new |
| — | `Services/ThumbnailCache.swift` | new |
| — | `Tests/Smoke/main.swift`, `smoke-test.sh`, `.swift-format` | new |

Type renames: `Thumb` → `Thumbnail`, `GeneralPrefs` → `GeneralPreferences`,
`RecentsPrefs` → `RecentsPreferences`, `FavoritesPrefs` → `FavoritesPreferences`,
`StreamResolver.resolveYouTubeKit` → `resolveYouTube`.

## Bugs Found

### Fixed (approved)
1. **`.pls` advertised but unplayable** — `StreamResolver.directExtensions`
   and the README listed `.pls` as a direct format, but `AVPlayer` cannot
   resolve PLS playlists. Verified with `AVURLAsset`: a local `.pls` reports
   `isPlayable == true` yet exposes **0 audio tracks**, so nothing plays.
   Removed `.pls` from the format list and the README.
2. **Stale metadata after Stop** — `AudioPlayer.stop()` cleared neither
   `title`/`sourceURL`/`artwork` nor `MPNowPlayingInfoCenter.nowPlayingInfo`,
   so the card and Control Center kept showing the old track while idle. It now
   clears all of them.
3. **Inconsistent thumbnail size** — favorites stored 256 px covers while
   recents downscaled the same image to 96 px. Both now use
   `ThumbnailCache.maxSide` (256).
4. **`Package.resolved` gitignored** — the `YouTubeKit` pin was not tracked, so
   a fresh checkout could resolve a different revision. Now tracked.

### Found but NOT fixed (left as-is to preserve behavior)
- **User-Agent vs version mismatch** — `ICYMetadata` sent `Airwave/1.1` while
  the bundle version is `1.1.0`. Centralized as `AppInfo.userAgent` but kept
  the literal `"Airwave/1.1"` to avoid changing outbound requests.
- **Duplicate version source** — `make-app.sh` hardcodes `VERSION=1.1.0`
  separately from `AppInfo.version`; a shell script can't read Swift constants,
  so they can still drift.
- **Silent duplicate favorite** — `FavoritesStore.add` no-ops when the URL
  already exists, but `AddFavoriteSheet` still dismisses as if it saved.
- **Empty-URL favorites** — `FavoritesPreferences.add()` creates favorites with
  an empty URL; export includes them but `FavoritesIO.merge` skips empty URLs on
  import (asymmetric round-trip).
- **Recents thumbnails on load** — items loaded from disk are not re-downscaled
  on launch; they rely on having been canonicalized when first stored.

## Risky Areas (worth a human review)

- `AudioPlayer`'s generation counter and restore-on-failure path are subtle and
  are not covered by automated tests.
- `TitlebarAccessoryInstaller`'s AppKit window/accessory lifecycle.
- `ICYMetadata`'s byte-stream parsing loop.
- The `swift format` pass reformatted some control-flow expressions
  (e.g. `Button { ... } label:` onto multiple lines). Cosmetic only, but it is
  the largest single diff in the branch.

## Suggested Follow-ups (out of scope)

- Add real XCTest/Swift Testing coverage when the project is built with Xcode.
- Consider unifying `Favorite` and `RecentTrack` (kept separate on purpose here).
- Implement PLS parsing if `.pls` support is actually wanted.
- Derive the version in `make-app.sh` from a single source of truth.

## Verification

### Testing approach
XCTest and Swift Testing are **not** available with the Command Line Tools
toolchain (they require full Xcode). `swift test` fails with
`no such module 'XCTest'`. As a fallback, `smoke-test.sh`:
1. runs `swift build -c release`, and
2. compiles a small harness (`Tests/Smoke/main.swift`) against the
   Foundation-only logic (`Prefs`, `Favorite`, `FavoritesIO`,
   `ThumbnailCache`, `UserDefaultsJSON`, `NSImage+Downsizing`) and asserts its
   behavior (7 checks).

### Results
| Check | Before | After |
| --- | --- | --- |
| `swift build -c release` | pass | pass |
| `./smoke-test.sh` | n/a (no tests) | pass (7/7) |
| `swift format lint --recursive Sources` | n/a | clean |
| `./make-app.sh` | pass | pass (bundle contains binary, plist, icon) |
| Tests | none | smoke script only |

### Manual checks
- `./make-app.sh` produced `dist/Airwave.app` with `Contents/MacOS/Airwave`,
  `Info.plist` and `AppIcon.icns`.
- The app was not launched interactively (headless environment); GUI flows
  (playback, title bar, settings) were not manually exercised.
