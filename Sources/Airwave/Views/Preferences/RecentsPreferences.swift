import SwiftUI

/// Recents settings: how many tracks to remember, and clearing history.
struct RecentsPreferences: View {
    @EnvironmentObject var recents: RecentsStore
    @State private var confirmClear = false

    /// Slider position while dragging. The stored size changes only when the drag
    /// ends, so history is not trimmed and re-saved on every tick.
    @State private var draftMaxCount: Double?

    private var sliderValue: Binding<Double> {
        Binding(
            get: { draftMaxCount ?? Double(recents.maxCount) },
            set: { draftMaxCount = $0.rounded() })
    }

    var body: some View {
        Form {
            LabeledContent("History size") {
                HStack(spacing: 8) {
                    Slider(
                        value: sliderValue,
                        in: Double(Prefs.minRecentMaxCount)...Double(Prefs.maxRecentMaxCount),
                        step: 1,
                        onEditingChanged: { editing in
                            guard !editing, let draftMaxCount else { return }
                            recents.maxCount = Int(draftMaxCount)
                            self.draftMaxCount = nil
                        }
                    )
                    .frame(width: 160)
                    Text("\(Int(draftMaxCount ?? Double(recents.maxCount)))")
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
        .confirmationDialog("Clear recent history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { recents.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all \(recents.items.count) recently played track(s).")
        }
    }
}
