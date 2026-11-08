import SwiftUI

/// Recents settings: how many tracks to remember, and clearing history.
struct RecentsPreferences: View {
    @EnvironmentObject var library: TrackLibrary
    @State private var confirmClear = false

    private var maxCountBinding: Binding<Double> {
        Binding(
            get: { Double(library.maxCount) },
            set: { library.maxCount = Int($0.rounded()) })
    }

    var body: some View {
        Form {
            LabeledContent("History size") {
                HStack(spacing: 8) {
                    Slider(
                        value: maxCountBinding,
                        in: Double(Prefs.minRecentMaxCount)...Double(Prefs.maxRecentMaxCount),
                        step: 1
                    )
                    .frame(width: 160)
                    Text("\(library.maxCount)")
                        .monospacedDigit()
                        .frame(width: 22, alignment: .trailing)
                }
            }
            .help("How many recently played tracks to remember for quick play.")

            LabeledContent("Clear history") {
                Button("Clear Recent Tracks", role: .destructive) { confirmClear = true }
                    .disabled(library.recents.isEmpty)
                    .help("Remove all recently played tracks.")
            }
            .help("Removes every entry from the Recents list.")
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear recent history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { library.clearRecents() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all \(library.recents.count) recently played track(s).")
        }
    }
}
