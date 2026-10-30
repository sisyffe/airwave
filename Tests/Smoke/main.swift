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
}

// MARK: FavoritesIO

do {
    let items = [
        Favorite(name: "Station One", url: "https://example.com/one.mp3", thumbnail: Data([1, 2, 3])),
        Favorite(name: "Station Two", url: "https://example.com/two.m3u8", thumbnail: nil)
    ]

    let decoded = try! FavoritesIO.decode(FavoritesIO.encode(items))
    check(decoded == items, "encode/decode round-trips favorites losslessly")

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
