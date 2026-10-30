import SwiftUI

/// Settings window: General, Recents and Favorites tabs.
struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferences().tabItem { Label("General", systemImage: "gearshape") }
            RecentsPreferences().tabItem { Label("Recents", systemImage: "clock.arrow.circlepath") }
            FavoritesPreferences().tabItem { Label("Favorites", systemImage: "star") }
        }
        .frame(width: 560, height: 380)
    }
}
