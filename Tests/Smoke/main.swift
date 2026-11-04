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

    check(
        Prefs.thumbnailDisplayMode(using: defaults) == .fill,
        "thumbnail display defaults to fill when unset"
    )
    defaults.set(ThumbnailDisplayMode.blurredFill.rawValue, forKey: Prefs.thumbnailDisplayMode)
    check(
        Prefs.thumbnailDisplayMode(using: defaults) == .blurredFill,
        "thumbnail display respects a stored value"
    )
    defaults.set("nonsense", forKey: Prefs.thumbnailDisplayMode)
    check(
        Prefs.thumbnailDisplayMode(using: defaults) == .fill,
        "an unrecognized thumbnail display falls back to fill"
    )

    check(
        Prefs.slowLoadRefreshSeconds(using: defaults) == Prefs.defaultSlowLoadRefreshSeconds,
        "slow-load refresh defaults to 4 seconds"
    )
    defaults.set(0, forKey: Prefs.slowLoadRefreshSeconds)
    check(Prefs.slowLoadRefreshSeconds(using: defaults) == 0, "slow-load refresh can be disabled")
    defaults.set(99, forKey: Prefs.slowLoadRefreshSeconds)
    check(
        Prefs.slowLoadRefreshSeconds(using: defaults) == Prefs.defaultSlowLoadRefreshSeconds,
        "an out-of-range slow-load delay falls back to the default"
    )
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
        json.allSatisfy { Set($0.keys) == Set(["name", "url"]) },
        "export includes only favorite name and URL"
    )

    let decoded = try! FavoritesIO.decode(encoded)
    let metadataRoundTrips = decoded.count == items.count
        && zip(decoded, items).allSatisfy { exported, original in
            exported.name == original.name && exported.url == original.url
        }
    check(
        metadataRoundTrips,
        "export/import preserves favorite metadata"
    )
    check(decoded.allSatisfy { $0.thumbnail == nil }, "imported favorites have no exported thumbnail")
    check(
        decoded.map(\.id) != items.map(\.id),
        "import regenerates favorite UUIDs"
    )

    // A duplicate link under a different name is allowed and kept; an exact
    // (name, link, trim) match is auto-merged.
    let incoming = [
        Favorite(name: "Station One", url: "https://example.com/one.mp3"),
        Favorite(name: "Duplicate", url: "https://example.com/one.mp3"),
        Favorite(name: "New", url: "https://example.com/three.aac"),
        Favorite(name: "Empty", url: "")
    ]
    let merged = FavoritesIO.merge(incoming, into: items)
    check(merged.added == 2, "merge adds new identities and skips exact duplicates")
    check(
        merged.items.map(\.url) == [
            "https://example.com/one.mp3",
            "https://example.com/two.m3u8",
            "https://example.com/one.mp3",
            "https://example.com/three.aac"
        ],
        "merge preserves existing order and appends new entries"
    )
    check(
        merged.items.map(\.name) == ["Station One", "Station Two", "Duplicate", "New"],
        "merge suffixes only on name collisions"
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

// MARK: FavoritesIO conflict handling

do {
    let existing = [Favorite(name: "Station One", url: "https://example.com/one.mp3")]
    let incoming = [
        Favorite(name: "Station One", url: "https://example.com/one.mp3"),
        Favorite(name: "Station One", url: "https://example.com/three.aac"),
        Favorite(name: "Other", url: "https://example.com/two.mp3")
    ]
    let plan = FavoritesIO.plan(incoming, into: existing)
    check(plan.duplicates == 1, "an exact duplicate is auto-merged")
    check(plan.additions.count == 1 && plan.additions.first?.name == "Other", "non-conflicting entries are additions")
    check(
        plan.conflicts.count == 1 && plan.conflicts.first?.url == "https://example.com/three.aac",
        "a same-name, different link is a conflict"
    )

    let suffixed = FavoritesIO.apply(plan, policy: .suffix, to: existing)
    check(suffixed.added == 2, "suffix adds both the addition and the conflict")
    check(suffixed.items.map(\.name) == ["Station One", "Other", "Station One 2"], "suffix keeps names unique")

    let skipped = FavoritesIO.apply(plan, policy: .skip, to: existing)
    check(skipped.added == 1 && skipped.items.count == 2, "skip drops conflicts but keeps additions")

    let overwritten = FavoritesIO.apply(plan, policy: .overwrite, to: existing)
    check(overwritten.items.first?.url == "https://example.com/three.aac", "overwrite replaces the existing favorite")
    check(Set(overwritten.items.map(\.name)).count == overwritten.items.count, "overwrite keeps names unique")
}

// MARK: FavoriteNaming

do {
    check(
        FavoriteNaming.unique("Jazz", url: "https://example.com/j", taken: []) == "Jazz",
        "a free name is kept"
    )
    check(
        FavoriteNaming.unique("Jazz", url: "https://example.com/j", taken: ["Jazz"]) == "Jazz 2",
        "a taken name is suffixed"
    )
    check(
        FavoriteNaming.unique("Jazz", url: "https://example.com/j", taken: ["Jazz", "Jazz 2"]) == "Jazz 3",
        "suffixing skips existing numbered names"
    )
    check(
        FavoriteNaming.unique("   ", url: "https://example.com/j", taken: []) == "https://example.com/j",
        "a blank name falls back to the URL"
    )
}

// MARK: Favorite identity

do {
    let base = Favorite(name: "Song", url: "https://example.com/s.mp3")
    let sameTrim = Favorite(name: "Song", url: "https://example.com/s.mp3", startOffset: 30, endOffset: 60)
    let otherTrim = Favorite(name: "Song", url: "https://example.com/s.mp3", startOffset: 90, endOffset: 60)
    check(base.identityKey == Favorite(name: "Song", url: "https://example.com/s.mp3").identityKey, "identity ignores the UUID")
    check(base.identityKey != sameTrim.identityKey, "different trim offsets are different identities")
    check(sameTrim.identityKey != otherTrim.identityKey, "different trims of one link are distinct")
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

// MARK: Volume

do {
    check(Volume.stops == [0, 0.25, 0.5, 0.75, 1.0], "volume has five evenly spaced stops")
    check(Volume.stops.last == Volume.maximum, "the last stop is the maximum")
    check(Volume.stops.first == 0, "the first stop is zero")
}

// MARK: StreamSniffer

do {
    check(
        StreamSniffer.kind(forMimeType: "application/vnd.apple.mpegurl; charset=utf-8") == .hls,
        "HLS MIME types classify as hls"
    )
    check(StreamSniffer.kind(forMimeType: "audio/mpeg") == .audio, "audio MIME types classify as audio")
    check(StreamSniffer.kind(forMimeType: "application/octet-stream") == .audio, "octet-stream classifies as audio")
    check(StreamSniffer.kind(forMimeType: "text/html") == .page, "HTML MIME types classify as page")
    check(StreamSniffer.kind(forMimeType: nil) == nil, "a missing MIME type is inconclusive")
    check(
        StreamSniffer.kind(forBody: Data("#EXTM3U\n#EXT-X-VERSION:3".utf8), mimeType: nil) == .hls,
        "an #EXTM3U body classifies as hls"
    )
    check(
        StreamSniffer.kind(forBody: Data("<!DOCTYPE html><html>".utf8), mimeType: nil) == .page,
        "an HTML body classifies as page"
    )
    check(
        StreamSniffer.kind(forBody: Data([0x00, 0x01, 0x02, 0x03]), mimeType: nil) == nil,
        "an unknown body is inconclusive"
    )
}

// MARK: ICYMetadata

do {
    check(ICYMetadata.isEligible(URL(string: "https://example.com/stream.mp3")!), "mp3 is ICY-eligible")
    check(!ICYMetadata.isEligible(URL(string: "https://example.com/stream.m3u8")!), "m3u8 is not ICY-eligible")
    check(
        ICYMetadata.isEligible(URL(string: "https://example.com/live")!, contentType: "audio/mpeg"),
        "an extensionless audio stream is ICY-eligible"
    )
    check(
        !ICYMetadata.isEligible(URL(string: "https://example.com/live")!, contentType: "application/vnd.apple.mpegurl"),
        "an extensionless HLS stream is not ICY-eligible"
    )

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
