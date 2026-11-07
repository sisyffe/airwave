import SwiftUI

/// Playback settings: end-of-track behavior and the seek controls shown in the
/// player card's popover.
struct PlaybackPreferences: View {
    @AppStorage(Prefs.replayOnTrackEnd) private var replayOnTrackEnd = Prefs.defaultReplayOnTrackEnd
    @AppStorage(Prefs.showExtraSeekControls) private var showExtraSeekControls =
        Prefs.defaultShowExtraSeekControls

    var body: some View {
        Form {
            Picker("When a track ends", selection: $replayOnTrackEnd) {
                Text("Replay from the start").tag(true)
                Text("Stop").tag(false)
            }
            .pickerStyle(.radioGroup)
            .help("Applies to finite tracks only; live streams never end.")

            Toggle("Show more fast-forward/rewind controls", isOn: $showExtraSeekControls)
                .help("Adds a second row of seek buttons (±1.5 min and ±5 min) to the player card's popover.")
        }
        .formStyle(.grouped)
    }
}
