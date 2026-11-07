import SwiftUI
import AppKit

/// Rounded thumbnail with a music-note fallback when there is no image data.
struct Thumbnail: View {
    let data: Data?
    var size: CGFloat

    /// Fallback icon size and corner radius, as fractions of `size`.
    private static let iconScale: CGFloat = 0.4
    private static let cornerRadiusScale: CGFloat = 0.12

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * Self.iconScale))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * Self.cornerRadiusScale))
    }
}
