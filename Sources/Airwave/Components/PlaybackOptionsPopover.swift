import SwiftUI

/// Seek controls shown from the arrow in the top-right of the playing card.
/// Disabled for live streams, which have no seekable timeline.
///
/// Observes the shared player directly rather than through `@EnvironmentObject`,
/// because popover content does not reliably receive environment updates.
struct PlaybackOptionsPopover: View {
    @ObservedObject private var player = AudioPlayer.shared
    @AppStorage(Prefs.showExtraSeekControls) private var showExtraSeekControls =
        Prefs.defaultShowExtraSeekControls

    private static let shortSkip: TimeInterval = 30
    private static let regularSkip: TimeInterval = 10
    private static let mediumSkip: TimeInterval = 90
    private static let longSkip: TimeInterval = 300

    var body: some View {
        controls
            .padding(12)
            .frame(minWidth: 190)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Controls").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                skipButton(
                    by: -Self.shortSkip, symbol: "gobackward.30", size: 15, help: "Rewind 30 seconds")
                skipButton(
                    by: -Self.regularSkip, symbol: "gobackward.10", size: 22, help: "Rewind 10 seconds")
                skipButton(by: Self.regularSkip, symbol: "goforward.10", size: 22, help: "Forward 10 seconds")
                skipButton(by: Self.shortSkip, symbol: "goforward.30", size: 15, help: "Forward 30 seconds")
            }
            .frame(maxWidth: .infinity)
            if showExtraSeekControls {
                HStack(spacing: 12) {
                    skipButton(by: -Self.longSkip, symbol: "gobackward.5", size: 15, help: "Rewind 5 minutes")
                    skipButton(by: -Self.mediumSkip, symbol: "gobackward.90", size: 22, help: "Rewind 1.5 minutes")
                    skipButton(by: Self.mediumSkip, symbol: "goforward.90", size: 22, help: "Forward 1.5 minutes")
                    skipButton(by: Self.longSkip, symbol: "goforward.5", size: 15, help: "Forward 5 minutes")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .disabled(player.isLive)
    }

    private func skipButton(by seconds: TimeInterval, symbol: String, size: CGFloat, help: String) -> some View {
        Button {
            player.skip(by: seconds)
        } label: {
            Image(systemName: symbol).font(.system(size: size))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
