import SwiftUI

/// Recents settings: how many tracks to remember, and clearing history.
struct RecentsPreferences: View {
    @EnvironmentObject var recents: RecentsStore
    @State private var confirmClear = false
    /// Local mirror of the slider value so dragging never fights the store's
    /// clamping (which otherwise steps the thumb back mid-drag).
    @State private var historySize: Double = Double(Prefs.defaultRecentMaxCount)

    var body: some View {
        Form {
            LabeledContent("History size") {
                HStack(spacing: 8) {
                    Slider(
                        value: $historySize,
                        in: Double(Prefs.minRecentMaxCount)...Double(Prefs.maxRecentMaxCount),
                        step: 1
                    )
                    .frame(width: 160)
                    .onChange(of: historySize) { value in
                        recents.maxCount = Int(value.rounded())
                    }
                    Text("\(Int(historySize.rounded()))")
                        .monospacedDigit()
                        .frame(width: 22, alignment: .trailing)
                }
            }
            .help("How many recently played tracks to remember for quick play.")

            LabeledContent("Clear history") {
                Button("Clear Recent Tracks", role: .destructive) { confirmClear = true }
                    .disabled(recents.items.isEmpty)
                    .help("Remove all recently played tracks.")
            }
            .help("Removes every entry from the Recents list.")
        }
        .formStyle(.grouped)
        .onAppear { historySize = Double(recents.maxCount) }
        .onChange(of: recents.maxCount) { historySize = Double($0) }
        .confirmationDialog("Clear recent history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { recents.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all \(recents.items.count) recently played track(s).")
        }
    }
}
