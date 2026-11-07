import SwiftUI

/// Playback settings: end-of-track behavior and the seek controls shown in the
/// player card's popover.
struct PlaybackPreferences: View {
    @AppStorage(Prefs.replayOnTrackEnd) private var replayOnTrackEnd = Prefs.defaultReplayOnTrackEnd
    @AppStorage(Prefs.showExtraSeekControls) private var showExtraSeekControls =
        Prefs.defaultShowExtraSeekControls
    @AppStorage(Prefs.manualLinkBehavior) private var manualLinkBehavior = Prefs.defaultManualLinkBehavior.rawValue

    var body: some View {
        Form {
            Picker("When a track ends", selection: $replayOnTrackEnd) {
                Text("Replay from the start").tag(true)
                Text("Stop").tag(false)
            }
            .pickerStyle(.radioGroup)
            .help("Applies to finite tracks only; live streams never end.")

            Picker("When a known link is entered manually", selection: $manualLinkBehavior) {
                Text("Play the matching favorite").tag(ManualLinkBehavior.playMatchingFavorite.rawValue)
                Text("Always play as a new track").tag(ManualLinkBehavior.alwaysNew.rawValue)
            }
            .pickerStyle(.radioGroup)
            .help(
                "A link matches a favorite only when it is the same URL and the favorite has no trim, or it is the only favorite using that URL."
            )

            Toggle("Show more fast-forward/rewind controls", isOn: $showExtraSeekControls)
                .help("Adds a second row of seek buttons (±1.5 min and ±5 min) to the player card's popover.")
        }
        .formStyle(.grouped)
    }
}
