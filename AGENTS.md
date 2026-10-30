# AGENTS.md

Guidance for agents working on **Airwave**, a lightweight native macOS audio
player (SwiftUI, macOS 14+) that plays direct audio/HLS streams and resolves
YouTube audio via `YouTubeKit`.

## Toolchain and constraints

- **No Xcode.** The project is a plain Swift package built with the Command Line
  Tools toolchain. `swift build`, `swift run`, `swift package` and `swift format`
  are available; **XCTest and Swift Testing are not** (`swift test` fails with
  `no such module 'XCTest'`). Do not add a `.testTarget`.
- `swift-tools-version` is 5.9. If you bump it to 6.0, remember that
  `Package.directoryURL` becomes available but Swift 6 language mode may turn on
  strict concurrency — pin `swiftLanguageModes` if needed.
- Do not add dependencies without asking. The only dependency is `YouTubeKit`.

## Layout

```
Sources/Airwave/
├── AirwaveApp.swift     # @main entry, WindowGroup, menu commands, AppDelegate
├── Services/            # stateful services + persistence
├── Utilities/           # small, dependency-free helpers
├── Views/               # window + settings screens
│   └── Preferences/     # one file per settings tab
└── Components/          # reusable SwiftUI views
Tests/Smoke/main.swift   # pure-logic smoke checks (run by smoke-test.sh)
Plugins/BundleApp/       # `swift package bundle` command plugin
```

Organize **by layer**, one clear responsibility per file. `Favorite`/
`RecentTrack` and their stores are intentionally kept separate but similar;
share code (e.g. `ThumbnailCache`, `UserDefaultsJSON`) rather than merging them.

## Commands

```bash
swift build -c release                                   # build
./smoke-test.sh                                          # build + format lint + logic checks
swift package --allow-writing-to-package-directory bundle # package dist/Airwave.app
swift run                                                # run unbundled (About shows version "dev")
swift format --in-place --recursive Sources              # format
swift format lint --recursive Sources                    # check formatting
```

- The bundle command plugin **packages an already-built binary**; run
  `swift build -c release` first. It needs `--allow-writing-to-package-directory`
  because it writes `dist/`.
- Do **not** make the plugin invoke `swift build`: nested SwiftPM invocations
  deadlock on the package lock, and command plugins are sandboxed so a nested
  `swift build` also fails. That is why packaging is a separate step.

## Versioning

`VERSION` at the repo root is the single source of truth. The bundle plugin
writes it into `Info.plist`; `AppInfo.version` reads it back at runtime from
`CFBundleShortVersionString` (falling back to `"dev"` when run unbundled). Bump
only `VERSION` (and the README badge).

## Tests

`smoke-test.sh` builds, runs `swift format lint`, then compiles
`Tests/Smoke/main.swift` together with the Foundation-only sources and runs the
checks. To cover new pure logic:

1. Add `check(...)` assertions in `Tests/Smoke/main.swift`.
2. If you use a new source file, add it to the `swiftc` list in `smoke-test.sh`.

Only logic that does not need AppKit, AVFoundation, or the network can be tested
here. If you change behaviour that is not covered, note it in the PR/commit.

## Conventions

- Match the existing style; `swift format` (config in `.swift-format`, 4-space
  indent) is the authority. Run it before committing.
- Names reveal intent: verbs for functions, nouns for values, booleans read as
  questions. No abbreviations (`fav`, `gen`, `req`) and no magic numbers —
  name them as constants.
- Comments explain **why**, not what. Keep doc comments on public/internal types
  and non-obvious methods.
- No comments that restate code, no commented-out code.

## Stability to preserve

- **Favorites JSON format** (`FavoritesIO`): exported files must round-trip.
  Draft favorites with an empty URL are excluded on both export and import.
- **UserDefaults keys** live in `Prefs`; don't change their string values.
- **`StreamResolver.directExtensions`**: only formats `AVPlayer` can actually
  play. `.pls` is deliberately unsupported (AVPlayer cannot resolve PLS).

## Known behaviour to keep in mind

- Playback async work is guarded by `PlaybackGeneration`. Any new `await` in the
  playback path must re-check `generation.isCurrent(token)` before touching
  state, and `stop()` must invalidate the generation.
- Favorites and recents store thumbnails through `ThumbnailCache`, which owns
  the canonical size. Never store raw/undownscaled image data.
- `stop()` clears `Prefs.lastURL` so hotstart does not restart a stopped stream.
  The resume URL is written in `AudioPlayer.start()`.
- When a finite item ends, `AudioPlayer` observes
  `AVPlayerItem.didPlayToEndTimeNotification` and either replays it or stops,
  per the `Prefs.replayOnTrackEnd` setting (default: replay). Live streams are
  indefinite and never post that notification.

## Committing

Small, single-purpose commits (`fix:`, `refactor:`, `build:`, `docs:`, `test:`).
Run `./smoke-test.sh` before committing. Do not commit unless asked.
