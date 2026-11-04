import SwiftUI
import AppKit

/// Routes "Show in Settings" requests to the Favorites settings tab, selecting
/// the requested favorite once the Settings window appears.
@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()

    /// The favorite to select when the Settings window next appears. Cleared by
    /// `FavoritesPreferences` after it consumes it.
    @Published var pendingFavoriteID: Favorite.ID?

    private init() {}

    /// Opens Settings focused on `favoriteID`.
    func show(favoriteID: Favorite.ID) {
        pendingFavoriteID = favoriteID
        // Works on macOS 13 and 14; `openSettings` is unavailable in a singleton.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
