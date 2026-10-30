import SwiftUI

/// Playback settings: what happens when a finite track finishes.
struct PlaybackPreferences: View {
    @AppStorage(Prefs.replayOnTrackEnd) private var replayOnTrackEnd = Prefs.defaultReplayOnTrackEnd

    var body: some View {
        Form {
            Picker("When a track ends", selection: $replayOnTrackEnd) {
                Text("Replay from the start").tag(true)
                Text("Stop").tag(false)
            }
            .pickerStyle(.radioGroup)
            .help("Applies to finite tracks only; live streams never end.")
        }
        .formStyle(.grouped)
    }
}
