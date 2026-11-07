import SwiftUI

/// Settings window: General, Playback, Recents and Favorites tabs. The selected
/// tab and favorite are driven by `SettingsRouter`.
struct PreferencesView: View {
    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        TabView(selection: $router.selectedTab) {
            GeneralPreferences()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsRouter.Tab.general)
            PlaybackPreferences()
                .tabItem { Label("Playback", systemImage: "play.circle") }
                .tag(SettingsRouter.Tab.playback)
            RecentsPreferences()
                .tabItem { Label("Recents", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsRouter.Tab.recents)
            FavoritesPreferences()
                .tabItem { Label("Favorites", systemImage: "star") }
                .tag(SettingsRouter.Tab.favorites)
        }
        .frame(width: 560, height: 380)
    }
}
