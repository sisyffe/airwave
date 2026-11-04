import SwiftUI

/// Playback settings: end-of-track behavior and the seek controls shown in the
/// player card's popover.
struct PlaybackPreferences: View {
    @AppStorage(Prefs.replayOnTrackEnd) private var replayOnTrackEnd = Prefs.defaultReplayOnTrackEnd
    @AppStorage(Prefs.showExtraSeekControls) private var showExtraSeekControls =
        Prefs.defaultShowExtraSeekControls
    @AppStorage(Prefs.slowLoadRefreshSeconds) private var slowLoadRefreshSeconds =
        Prefs.defaultSlowLoadRefreshSeconds

    private var refreshOptions: [Int] { Prefs.slowLoadRefreshOptions }

    private var refreshIndexBinding: Binding<Double> {
        Binding(
            get: {
                let index = refreshOptions.firstIndex(of: slowLoadRefreshSeconds)
                    ?? refreshOptions.firstIndex(of: Prefs.defaultSlowLoadRefreshSeconds) ?? 0
                return Double(index)
            },
            set: { slowLoadRefreshSeconds = refreshOptions[Int($0.rounded())] }
        )
    }

    private var refreshLabel: String {
        slowLoadRefreshSeconds == 0 ? "Never" : "\(slowLoadRefreshSeconds) s"
    }

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

            LabeledContent("Auto-refresh slow loads") {
                HStack(spacing: 8) {
                    Slider(value: refreshIndexBinding, in: 0...Double(refreshOptions.count - 1), step: 1)
                        .frame(width: 160)
                    Text(refreshLabel)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .help("Reload the stream if it is still loading after this delay. Never disables it.")
        }
        .formStyle(.grouped)
    }
}
