/// Guards asynchronous playback work against superseded or cancelled requests.
///
/// Each new `begin()` hands out a token. Callers capture the token and re-check
/// `isCurrent(_:)` after every `await`; a newer `begin()` or an `invalidate()`
/// makes all outstanding tokens stale, so late results are dropped.
struct PlaybackGeneration {
    private var current = 0

    /// Starts a new generation and returns its token.
    mutating func begin() -> Int {
        current += 1
        return current
    }

    /// Invalidates every outstanding token without starting a new generation.
    /// Used when playback is stopped so in-flight work is discarded.
    mutating func invalidate() {
        current += 1
    }

    /// Whether `token` still refers to the latest generation.
    func isCurrent(_ token: Int) -> Bool {
        token == current
    }
}
