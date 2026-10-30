import SwiftUI

/// Settings window: General, Playback, Recents and Favorites tabs.
struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferences().tabItem { Label("General", systemImage: "gearshape") }
            PlaybackPreferences().tabItem { Label("Playback", systemImage: "play.circle") }
            RecentsPreferences().tabItem { Label("Recents", systemImage: "clock.arrow.circlepath") }
            FavoritesPreferences().tabItem { Label("Favorites", systemImage: "star") }
        }
        .frame(width: 560, height: 380)
    }
}
