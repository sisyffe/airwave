# Airwave Refactoring Plan

Goal: make every file easy to understand in a minute or two, without changing
behavior. Public API, CLI flags, and the favorites JSON format are preserved.
The four known bugs below are fixed as explicitly approved.

## Baseline

- `swift build -c release` — passes.
- No test target exists.
- No formatter/linter configured (`swift format` is bundled with the toolchain).

## Problems Found

### Organization
- `Views/PreferencesView.swift` (243 lines) holds 4 view types.
- `Components/TitlebarAccessory.swift` mixes a network service, a view, and an AppKit bridge.
- `Services/StreamResolver.swift` also defines an `NSImage` utility used elsewhere.
- Stray `.DS_Store` files under `Sources/`.

### Duplication
- JSON → UserDefaults persistence duplicated in `FavoritesStore` and `RecentsStore`.
- Thumbnail downscaling duplicated/inconsistent (256 px vs 96 px).

### Naming / constants
- Abbreviations: `conn`, `fav`, `gen`, `metaInt`, `req`, `re`/`m`/`r`, `q`, `on`, `s`.
- Magic values: thumbnail sizes, HTML byte cap, user-agent strings, app name/version.

### Long functions
- `AudioPlayer.play`, `FavoritesPrefs` body, `TitlebarAccessory.Coordinator`.

## Bugs (approved for fixing)
1. `.pls` advertised as playable but AVPlayer cannot play PLS playlists.
2. `AudioPlayer.stop()` leaves stale title/source/artwork and Now Playing info.
3. Thumbnail size inconsistency (favorites 256 px vs recents 96 px).
4. `Package.resolved` gitignored → YouTubeKit pin not tracked (build drift).

## Order of Work (one commit per step)

1. `test:` XCTest target + characterization tests.
2. `chore:` remove stray `.DS_Store` files.
3. `fix:` drop `.pls` from supported formats + README.
4. `fix:` clear metadata on `stop()`.
5. `fix:` track `Package.resolved`.
6. `refactor:` `Prefs.favorites` + `UserDefaultsJSON` helper.
7. `refactor:` move `NSImage.downsized` to `Utilities/`.
8. `refactor:` shared `ThumbnailCache` (JSON format unchanged).
9. `refactor:` split `ConnectionMonitor` into `Services/`.
10. `refactor:` split `PreferencesView` into `Views/Preferences/`.
11. `refactor:` rename `Thumb` → `Thumbnail`; de-abbreviate; named constants.
12. `refactor:` break up `AudioPlayer.play`.
13. `style:` add `.swift-format` and apply.
14. `docs:` update README; add `REFACTOR_NOTES.md`.

This file is deleted at the end.
