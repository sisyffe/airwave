import SwiftUI

/// Connection quality icon + settings gear for the title-bar row.
struct TitlebarButtons: View {
    @ObservedObject private var connection = ConnectionMonitor.shared
    let openSettings: () -> Void
    @State private var hovering = false

    private var quality: (label: String, color: Color, symbol: String) {
        switch connection.quality {
        case .good: return ("Connected", .green, "wifi")
        case .weak: return ("Weak connection", .yellow, "wifi.exclamationmark")
        case .offline: return ("No network", .red, "wifi.slash")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Hovering shows the quality immediately as colored text (a native
            // .help tooltip has an uncontrollable delay and cannot be colored).
            Image(systemName: quality.symbol)
                .foregroundStyle(quality.color)
                .onHover { hovering = $0 }
                .popover(isPresented: $hovering, arrowEdge: .bottom) {
                    Text(quality.label)
                        .font(.caption)
                        .foregroundStyle(quality.color)
                        .padding(6)
                }
                .accessibilityLabel(quality.label)
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Preferences (⌘,)")
        }
        .controlSize(.small)
        .padding(.trailing, 10)
    }
}
