import SwiftUI

/// Playback settings: how playback starts, what happens at the end of a track,
/// and how links typed by hand are matched to favorites.
struct PlaybackPreferences: View {
    @AppStorage(Prefs.hotstart) private var hotstart = true
    @AppStorage(Prefs.replayOnTrackEnd) private var replayOnTrackEnd = Prefs.defaultReplayOnTrackEnd
    @AppStorage(Prefs.manualLinkBehavior) private var manualLinkBehavior = Prefs.defaultManualLinkBehavior.rawValue
    @AppStorage(Prefs.autoRefreshSeconds) private var autoRefreshSeconds = Prefs.defaultAutoRefreshSeconds

    /// Index into `Prefs.autoRefreshStops`, so the slider moves in discrete steps.
    private var autoRefreshIndex: Binding<Double> {
        Binding(
            get: {
                let stops = Prefs.autoRefreshStops
                return Double(stops.firstIndex(of: autoRefreshSeconds) ?? stops.firstIndex(of: Prefs.defaultAutoRefreshSeconds) ?? 0)
            },
            set: { autoRefreshSeconds = Prefs.autoRefreshStops[Int($0.rounded())] })
    }

    private var autoRefreshLabel: String {
        autoRefreshSeconds == 0 ? "Never" : "\(Int(autoRefreshSeconds)) s"
    }

    var body: some View {
        Form {
            Section("Behaviour") {
                Toggle("Hotstart: play automatically when Airwave opens", isOn: $hotstart)
                    .help("Resumes the last played source")

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

                LabeledContent("Reload slow loads") {
                    HStack(spacing: 8) {
                        Slider(
                            value: autoRefreshIndex,
                            in: 0...Double(Prefs.autoRefreshStops.count - 1),
                            step: 1
                        )
                        .frame(width: 160)
                        Text(autoRefreshLabel)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .help("Restarts a load that has not started playing after this long, up to two times. Never disables it.")
            }
        }
        .formStyle(.grouped)
    }
}
