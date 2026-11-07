import SwiftUI

/// Appearance rows shown in the General tab: how thumbnails are displayed and
/// how many seek buttons the player card's popover shows.
struct AppearanceSettings: View {
    @AppStorage(Prefs.thumbnailDisplayMode) private var thumbnailDisplayMode = Prefs.defaultThumbnailDisplayMode.rawValue
    @AppStorage(Prefs.showExtraSeekControls) private var showExtraSeekControls =
        Prefs.defaultShowExtraSeekControls

    var body: some View {
        Picker("Thumbnails", selection: $thumbnailDisplayMode) {
            Text("Fill").tag(ThumbnailDisplayMode.fill.rawValue)
            Text("Fit").tag(ThumbnailDisplayMode.fit.rawValue)
        }
        .pickerStyle(.segmented)
        .help("Fill crops artwork to a square. Fit shows the whole image over a blurred copy of itself.")

        Toggle("Show more fast-forward/rewind controls", isOn: $showExtraSeekControls)
            .help("Adds a second row of seek buttons (±1.5 min and ±5 min) to the player card's popover.")
    }
}
