import SwiftUI

/// Lets code outside the Settings window (a favorite's "Show in Settings" menu,
/// the failed-favorite alert) choose the tab and the favorite that Settings shows.
@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()

    enum Tab: Hashable { case general, playback, recents, favorites }

    @Published var selectedTab: Tab = .general
    @Published var selectedFavoriteID: Favorite.ID?

    /// Routes Settings to the Favorites tab with `favorite` selected.
    func show(_ favorite: Favorite) {
        selectedFavoriteID = favorite.id
        selectedTab = .favorites
        SettingsWindow.open()
    }
}
