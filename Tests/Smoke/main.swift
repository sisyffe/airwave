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

// MARK: Track catalog

do {
    var catalog = TrackCatalog()
    check(TrackCatalog.nameKey("  Jazz ") == TrackCatalog.nameKey("jazz"), "name keys ignore case and spaces")
    check(TrackCatalog.nameKey("Jazz  Night") == TrackCatalog.nameKey("jazz night"), "name keys collapse inner spaces")

    let first = Track(name: "Jazz", url: "https://example.com/a.mp3")
    check(catalog.addFavorite(first, name: "Jazz"), "a favorite can be added")
    let clash = Track(name: "x", url: "https://example.com/a.mp3")
    check(!catalog.addFavorite(clash, name: " jazz "), "a taken name is rejected, case and spaces ignored")
    check(catalog.addFavorite(clash, name: "Jazz B"), "the same link can be saved again under another name")
    check(catalog.favorites.count == 2, "two favorites share a link")
    check(catalog.favorites[0].id == first.id, "a favorite keeps the identity of the saved track")

    check(!catalog.renameFavorite(clash.id, to: "JAZZ"), "renaming to a taken name is rejected")
    check(catalog.renameFavorite(clash.id, to: "Jazz C"), "renaming to a free name works")

    let draft = catalog.addDraft()
    let draft2 = catalog.addDraft()
    check(catalog.tracks[draft]?.name == "New Favorite", "first draft is named New Favorite")
    check(catalog.tracks[draft2]?.name == "New Favorite 2", "second draft gets a numeric suffix")

    // Trim persists after unfavoriting, and is read-only on non-favorites.
    var trimmed = TrackCatalog()
    let song = Track(name: "Song", url: "https://example.com/s.mp3")
    trimmed.addFavorite(song, name: "Song")
    trimmed.setTrim(song.id, start: 30, end: 60)
    trimmed.removeFavorite(song.id)
    check(trimmed.tracks[song.id] == nil, "an unfavorited track outside recents is forgotten")
    trimmed.recordPlayback(song)
    trimmed.addFavorite(song, name: "Song")
    trimmed.setTrim(song.id, start: 30, end: 60)
    trimmed.removeFavorite(song.id)
    check(trimmed.tracks[song.id]?.startOffset == 30, "trim survives unfavoriting while in recents")
    trimmed.setTrim(song.id, start: 5, end: 5)
    check(trimmed.tracks[song.id]?.startOffset == 30, "trim is not editable on a non-favorite")
    trimmed.addFavorite(song, name: "Song")
    check(trimmed.tracks[song.id]?.endOffset == 60, "re-favoriting restores the trim")

    // Recents
    var recents = TrackCatalog()
    recents.recentLimit = 2
    let one = Track(name: "1", url: "https://example.com/1.mp3")
    let two = Track(name: "2", url: "https://example.com/2.mp3")
    let three = Track(name: "3", url: "https://example.com/3.mp3")
    for track in [one, two, three] { recents.recordPlayback(track) }
    check(recents.recentOrder == [three.id, two.id], "recents are capped, newest first")
    check(recents.tracks[one.id] == nil, "an evicted non-favorite is dropped")
    recents.recordPlayback(two)
    check(recents.recentOrder == [two.id, three.id], "replaying moves a track to the front")

    // Resolution of links typed by hand
    var library = TrackCatalog()
    let plain = Track(name: "Plain", url: "https://example.com/p.mp3")
    var trimmedFavorite = Track(name: "Trimmed", url: "https://example.com/p.mp3")
    trimmedFavorite.startOffset = 10
    library.addFavorite(trimmedFavorite, name: "Trimmed")
    library.setTrim(trimmedFavorite.id, start: 10, end: nil)
    let link = "https://example.com/p.mp3"
    check(
        library.resolve(url: link, mode: .matchesClosest).id == trimmedFavorite.id,
        "closest: a trimmed favorite plays when it is the only match")
    check(library.resolve(url: link, mode: .exactlyMatches).id != trimmedFavorite.id, "exact: a trimmed favorite is not reused")
    library.addFavorite(plain, name: "Plain")
    check(library.resolve(url: link, mode: .matchesClosest).id == plain.id, "closest: prefers the favorite without trim")
    check(library.resolve(url: link, mode: .exactlyMatches).id == plain.id, "exact: reuses the favorite without trim")
    check(library.resolve(url: link, mode: .alwaysNew).id != plain.id, "always new: ignores favorites")
    library.recordPlayback(plain)
    library.removeFavorite(plain.id)
    check(library.resolve(url: link, mode: .alwaysNew).id != plain.id, "always new: ignores recents too")
    check(
        library.tracks[library.resolve(url: "https://example.com/new.mp3", mode: .matchesClosest).id] == nil,
        "unknown links become new tracks")

    // Import
    var target = TrackCatalog()
    target.addFavorite(Track(name: "Jazz", url: "https://example.com/j.mp3"), name: "Jazz")
    let incoming = [
        Track(name: "Jazz", url: "https://example.com/a.mp3"),
        Track(name: "jazz", url: "https://example.com/b.mp3"),
        Track(name: "Empty", url: ""),
    ]
    let added = target.importFavorites(incoming)
    check(added.count == 2, "import skips empty links")
    check(
        target.favorites.map(\.name) == ["Jazz", "Jazz 2", "jazz 3"],
        "import suffixes clashing names")
    check(Set(target.favorites.map(\.id)).count == 3, "imported favorites get new identities")
}

// MARK: FavoritesIO

do {
    var favorite = Track(name: "Trimmed", url: "https://example.com/t.mp3")
    favorite.startOffset = 30
    favorite.endOffset = 90
    let draft = Track(name: "Draft", url: "")
    let encoded = try! FavoritesIO.encode([favorite, draft])
    let json = try! JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]
    check(json.count == 1, "export skips empty-URL drafts")
    check(Set(json[0].keys) == Set(["name", "url", "startOffset", "endOffset"]), "export holds names, links and trims only")
    let decoded = try! FavoritesIO.decode(encoded)
    check(decoded.first?.startOffset == 30 && decoded.first?.endOffset == 90, "trims round-trip")
    check(decoded.first?.id != favorite.id, "import gives a new identity")
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
