// Characterization checks for Airwave's Foundation-only logic.
//
// This is compiled and run by `smoke-test.sh`, together with the pure-logic
// source files. It exists because XCTest/Swift Testing are not available with
// the Command Line Tools toolchain (full Xcode is required for those).
//
// Add checks here for logic that can be exercised without AppKit, AVFoundation,
// or the network.

import Foundation

var failures = 0

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok: \(message)")
    } else {
        print("  FAIL: \(message)")
        failures += 1
    }
}

// MARK: Prefs

do {
    let suite = "airwave.smoke.prefs"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)

    check(
        Prefs.shouldQuitAfterLastWindowClosed(using: defaults),
        "quit-on-last-window-closed defaults to true when unset"
    )

    defaults.set(false, forKey: Prefs.quitOnLastWindowClosed)
    check(
        !Prefs.shouldQuitAfterLastWindowClosed(using: defaults),
        "quit-on-last-window-closed respects an explicit false"
    )

    defaults.set(true, forKey: Prefs.quitOnLastWindowClosed)
    check(
        Prefs.shouldQuitAfterLastWindowClosed(using: defaults),
        "quit-on-last-window-closed respects an explicit true"
    )

    check(
        Prefs.minRecentMaxCount <= Prefs.defaultRecentMaxCount
            && Prefs.defaultRecentMaxCount <= Prefs.maxRecentMaxCount,
        "recent-history bounds are ordered"
    )

    check(
        Prefs.shouldReplayOnTrackEnd(using: defaults),
        "replay-on-track-end defaults to true when unset"
    )

    defaults.set(false, forKey: Prefs.replayOnTrackEnd)
    check(
        !Prefs.shouldReplayOnTrackEnd(using: defaults),
        "replay-on-track-end respects an explicit false"
    )

    defaults.set(true, forKey: Prefs.replayOnTrackEnd)
    check(
        Prefs.shouldReplayOnTrackEnd(using: defaults),
        "replay-on-track-end respects an explicit true"
    )

    check(!Prefs.defaultShowExtraSeekControls, "extra seek controls default to off")
}

// MARK: FavoritesIO

do {
    let items = [
        Favorite(name: "Station One", url: "https://example.com/one.mp3", thumbnail: Data([1, 2, 3])),
        Favorite(name: "Station Two", url: "https://example.com/two.m3u8", thumbnail: nil)
    ]

    let encoded = try! FavoritesIO.encode(items)
    let json = try! JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]
    check(
        json.allSatisfy { Set($0.keys) == Set(["id", "name", "url"]) },
        "export includes only favorite id, name, and URL"
    )

    let decoded = try! FavoritesIO.decode(encoded)
    let metadataRoundTrips = decoded.count == items.count
        && zip(decoded, items).allSatisfy { exported, original in
            exported.id == original.id && exported.name == original.name && exported.url == original.url
        }
    check(
        metadataRoundTrips,
        "export/import preserves favorite metadata"
    )
    check(decoded.allSatisfy { $0.thumbnail == nil }, "imported favorites have no exported thumbnail")

    let incoming = [
        Favorite(name: "Duplicate", url: "https://example.com/one.mp3"),
        Favorite(name: "New", url: "https://example.com/three.aac"),
        Favorite(name: "Empty", url: "")
    ]
    let merged = FavoritesIO.merge(incoming, into: items)
    check(merged.added == 1, "merge counts only new, non-empty URLs")
    check(
        merged.items.map(\.url) == [
            "https://example.com/one.mp3",
            "https://example.com/two.m3u8",
            "https://example.com/three.aac"
        ],
        "merge preserves existing order and appends new entries"
    )

    let exported = try! FavoritesIO.decode(FavoritesIO.encode(items + [Favorite(name: "Draft", url: "")]))
    check(exported.map(\.url) == items.map(\.url), "export skips empty-URL drafts (symmetric with import)")

    // Favorites stored by older versions (and exported files) have no
    // `hasCustomThumbnail` key; they must still decode rather than wipe the list.
    let legacyJSON = Data(
        #"[{"id":"8A9F1D2E-0000-4000-8000-000000000000","name":"Old","url":"https://example.com/old.mp3"}]"#.utf8)
    let legacy = try! FavoritesIO.decode(legacyJSON)
    check(legacy.count == 1, "legacy favorites JSON decodes")
    check(legacy.first?.hasCustomThumbnail == nil, "a missing custom-thumbnail flag decodes as nil")
    check(
        legacy.first?.startOffset == nil && legacy.first?.endOffset == nil,
        "missing trim offsets decode as nil"
    )
    check(legacy.first?.isFinite == nil, "a missing finiteness flag decodes as nil")

    let trimmed = Favorite(name: "Trimmed", url: "https://example.com/t.mp3", startOffset: 30, endOffset: 90)
    let roundTrip = try! FavoritesIO.decode(FavoritesIO.encode([trimmed]))
    check(
        roundTrip.first?.startOffset == 30 && roundTrip.first?.endOffset == 90,
        "trim offsets round-trip through export/import"
    )
}

// MARK: RecentTrack

do {
    let legacyJSON = Data(
        #"[{"id":"8A9F1D2E-0000-4000-8000-000000000000","name":"Old","url":"https://example.com/old.mp3"}]"#.utf8)
    let decoded = try! JSONDecoder().decode([RecentTrack].self, from: legacyJSON)
    check(decoded.count == 1, "legacy recent JSON decodes")
    check(decoded.first?.hasCustomThumbnail == nil, "a missing recent custom-thumbnail flag decodes as nil")
}

// MARK: PlaybackGeneration

do {
    var generation = PlaybackGeneration()
    let first = generation.begin()
    check(generation.isCurrent(first), "a fresh token is current")
    let second = generation.begin()
    check(!generation.isCurrent(first), "starting a new generation invalidates the old token")
    check(generation.isCurrent(second), "the newest token is current")

    generation.invalidate()
    check(!generation.isCurrent(second), "invalidate() makes outstanding tokens stale")
}

// MARK: URLValidation

do {
    check(
        URLValidation.httpURL(from: "https://example.com/audio.mp3") != nil,
        "valid HTTPS URLs are accepted"
    )
    check(
        URLValidation.httpURL(from: "  http://localhost:8000/stream  ") != nil,
        "valid HTTP URLs with surrounding whitespace are accepted"
    )
    check(URLValidation.httpURL(from: "") == nil, "empty input is rejected")
    check(URLValidation.httpURL(from: "example.com/audio.mp3") == nil, "relative URLs are rejected")
    check(URLValidation.httpURL(from: "ftp://example.com/audio.mp3") == nil, "non-HTTP schemes are rejected")
    check(URLValidation.httpURL(from: "https:///audio.mp3") == nil, "URLs without a host are rejected")
}

// MARK: ICYMetadata

do {
    check(ICYMetadata.isEligible(URL(string: "https://example.com/stream.mp3")!), "mp3 is ICY-eligible")
    check(!ICYMetadata.isEligible(URL(string: "https://example.com/stream.m3u8")!), "m3u8 is not ICY-eligible")

    func block(_ text: String) -> [UInt8] { Array(text.utf8) }
    check(
        ICYMetadata.parseStreamTitle(block("StreamTitle='Artist - Song';")) == "Artist - Song",
        "parseStreamTitle extracts the song"
    )
    check(
        ICYMetadata.parseStreamTitle(block("StreamTitle='   ';")) == nil,
        "parseStreamTitle treats a blank title as nil"
    )
    check(
        ICYMetadata.parseStreamTitle(block("no metadata here")) == nil,
        "parseStreamTitle returns nil without a StreamTitle"
    )
}

if failures > 0 {
    print("\(failures) smoke check(s) failed.")
    exit(1)
}
print("All smoke checks passed.")
