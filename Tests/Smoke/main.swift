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
        Favorite(name: "Station One", url: "https://example.com/one.mp3", thumbnailKey: "abc"),
        Favorite(name: "Station Two", url: "https://example.com/two.m3u8", thumbnailKey: nil),
    ]

    let encoded = try! FavoritesIO.encode(items)
    let json = try! JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]
    check(
        json.allSatisfy { Set($0.keys) == Set(["name", "url"]) },
        "export includes only favorite name and URL (no identifiers)"
    )

    let decoded = try! FavoritesIO.decode(encoded)
    let metadataRoundTrips =
        decoded.count == items.count
        && zip(decoded, items).allSatisfy { imported, original in
            imported.id != original.id && imported.name == original.name && imported.url == original.url
        }
    check(
        metadataRoundTrips,
        "export/import preserves favorite metadata and assigns fresh identifiers"
    )
    check(decoded.allSatisfy { $0.thumbnailKey == nil }, "imported favorites carry no artwork key")

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

// MARK: Track identity and the manual-link rule

do {
    let plain = Favorite(name: "Plain", url: "https://example.com/a.mp3")
    let trimmed = Favorite(name: "Trimmed", url: "https://example.com/a.mp3", startOffset: 10)
    let other = Favorite(name: "Other", url: "https://example.com/b.mp3")

    check(
        ManualLinkRule.match(url: "https://example.com/a.mp3", in: [plain], behavior: .playMatchingFavorite)?.id
            == plain.id,
        "a single untrimmed favorite with the link is matched"
    )
    check(
        ManualLinkRule.match(url: "https://example.com/a.mp3", in: [trimmed], behavior: .playMatchingFavorite)?.id
            == trimmed.id,
        "a single trimmed favorite is matched and keeps its trim"
    )
    check(
        ManualLinkRule.match(url: "https://example.com/a.mp3", in: [trimmed, plain], behavior: .playMatchingFavorite)?
            .id == plain.id,
        "with several favorites, the first untrimmed one is chosen"
    )
    check(
        ManualLinkRule.match(url: "https://example.com/a.mp3", in: [trimmed, trimmed], behavior: .playMatchingFavorite)
            == nil,
        "several trimmed favorites with no untrimmed one leave the link as a new track"
    )
    check(
        ManualLinkRule.match(url: "https://example.com/c.mp3", in: [other], behavior: .playMatchingFavorite) == nil,
        "a link with no favorite is a new track"
    )
    check(
        ManualLinkRule.match(url: "https://example.com/a.mp3", in: [plain], behavior: .alwaysNew) == nil,
        "the always-new setting ignores matching favorites"
    )

    let known = PlaybackRequest.known(
        trackID: plain.id, url: plain.url, favorites: [plain], recents: [])
    check(known.trackID == plain.id && known.name == "Plain", "a recent sharing a favorite's ID plays as that favorite")

    let unknownID = UUID()
    let unknownRequest = PlaybackRequest.known(trackID: unknownID, url: other.url, favorites: [plain], recents: [])
    check(unknownRequest.trackID == unknownID && unknownRequest.name == nil, "an unmatched recent plays as a plain track")

    check(Favorite.nameKey("  Radio One ") == Favorite.nameKey("radio one"), "names compare case-insensitively after trimming")
    check(
        !Favorite.isNameAvailable("RADIO ONE", among: [Favorite(name: "Radio One", url: "https://example.com/1.mp3")]),
        "a taken name is unavailable regardless of case"
    )
    check(
        Favorite.isNameAvailable("Radio One", among: [plain], excluding: plain.id),
        "a favorite can keep its own name"
    )

    let duplicateNamesJSON = Data(
        #"[{"name":"Same","url":"https://example.com/1.mp3"},{"name":"same","url":"https://example.com/2.mp3"}]"#.utf8)
    check((try? FavoritesIO.decode(duplicateNamesJSON)) == nil, "a file with duplicate names is rejected")

    let importedWithID = Data(
        #"[{"id":"8A9F1D2E-0000-4000-8000-000000000000","name":"Keyed","url":"https://example.com/k.mp3"}]"#.utf8)
    let imported = try! FavoritesIO.decode(importedWithID)
    check(imported.first?.id != UUID(uuidString: "8A9F1D2E-0000-4000-8000-000000000000"), "imported favorites get fresh IDs")
}

// MARK: StreamProbe

do {
    let hls = Array("#EXTM3U\n#EXT-X-VERSION:3".utf8)
    check(StreamProbe.isPlayable(contentType: nil, sample: hls), "an HLS playlist is accepted without a content type")
    check(
        StreamProbe.isPlayable(contentType: "audio/mpeg; charset=binary", sample: []),
        "an audio content type is accepted with parameters"
    )
    check(
        StreamProbe.isPlayable(contentType: "application/vnd.apple.mpegurl", sample: []),
        "an Apple HLS content type is accepted"
    )
    check(
        !StreamProbe.isPlayable(contentType: "text/html; charset=utf-8", sample: Array("<html>".utf8)),
        "an HTML page is rejected"
    )
    check(!StreamProbe.isPlayable(contentType: nil, sample: []), "an empty response without a type is rejected")
}

// MARK: FavoritesIO import plan

do {
    let existing = [
        Favorite(name: "Jazz", url: "https://example.com/jazz.mp3", startOffset: 5),
        Favorite(name: "News", url: "https://example.com/news.mp3"),
    ]
    let incoming = [
        Favorite(name: "jazz", url: "https://example.com/jazz2.mp3"),
        Favorite(name: "Rock", url: "https://example.com/rock.mp3"),
    ]
    let plan = FavoritesIO.plan(incoming, against: existing)
    check(plan.conflicts.count == 1, "a name conflict is detected case-insensitively")

    let duplicated = FavoritesIO.apply(plan, to: existing, strategy: .createDuplicates)
    check(
        duplicated.map(\.name) == ["Jazz", "News", "Rock", "jazz (2)"] || duplicated.map(\.name) == ["Jazz", "News", "jazz (2)", "Rock"],
        "create-duplicates suffixes the conflicting name and keeps file order")

    let ignored = FavoritesIO.apply(plan, to: existing, strategy: .ignore)
    check(ignored.map(\.name) == ["Jazz", "News", "Rock"], "ignore drops only the conflicting import")

    let overwritten = FavoritesIO.apply(plan, to: existing, strategy: .overwrite)
    check(
        overwritten.count == 3 && overwritten[0].url == "https://example.com/jazz2.mp3", "overwrite replaces the existing favorite in place"
    )
    check(overwritten[0].id != existing[0].id, "overwrite gives the favorite a new identity")
    check(overwritten[0].startOffset == nil, "overwrite takes the imported trim, not the old one")

    check(FavoritesIO.uniqueName(for: "Jazz", among: existing) == "Jazz (2)", "unique name starts at (2)")
    check(
        FavoritesIO.uniqueName(for: "Jazz", among: existing + [Favorite(name: "Jazz (2)", url: "x")]) == "Jazz (3)",
        "unique name skips numbers already in use"
    )
}

// MARK: Auto-refresh threshold

do {
    let suite = "airwave.smoke.autorefresh"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)

    check(Prefs.autoRefreshThreshold(using: defaults) == 4, "slow-load threshold defaults to 4 seconds")
    defaults.set(0.0, forKey: Prefs.autoRefreshSeconds)
    check(Prefs.autoRefreshThreshold(using: defaults) == nil, "a zero threshold means never")
    defaults.set(10.0, forKey: Prefs.autoRefreshSeconds)
    check(Prefs.autoRefreshThreshold(using: defaults) == 10, "an explicit threshold is respected")
    check(Prefs.autoRefreshStops.last == 0 && Prefs.autoRefreshStops.count == 7, "the stops are 2–10 s and never")
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
