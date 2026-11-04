import SwiftUI
import AppKit

/// Rounded thumbnail with a music-note fallback when there is no image data.
/// The fit is controlled by the `thumbnailDisplayMode` setting.
struct Thumbnail: View {
    let data: Data?
    var size: CGFloat

    @AppStorage(Prefs.thumbnailDisplayMode) private var displayMode: ThumbnailDisplayMode =
        Prefs.defaultThumbnailDisplayMode

    /// Fallback icon size and corner radius, as fractions of `size`.
    private static let iconScale: CGFloat = 0.4
    private static let cornerRadiusScale: CGFloat = 0.12
    /// Below this size a blurred fill reads as noise, so plain fit is used.
    private static let blurredFillMinimumSize: CGFloat = 48

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                imageView(image)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * Self.iconScale))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size, height: size)
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: size * Self.cornerRadiusScale))
    }

    @ViewBuilder private func imageView(_ image: NSImage) -> some View {
        switch displayMode {
        case .fill:
            Image(nsImage: image).resizable().scaledToFill()
        case .fit:
            Image(nsImage: image).resizable().scaledToFit()
        case .blurredFill:
            if size >= Self.blurredFillMinimumSize {
                ZStack {
                    Image(nsImage: image).resizable().scaledToFill().blur(radius: 8)
                    Image(nsImage: image).resizable().scaledToFit()
                }
            } else {
                Image(nsImage: image).resizable().scaledToFit()
            }
        }
    }

    /// A backing color is only needed where the image does not cover the square
    /// (fit/letterbox and the placeholder).
    private var backgroundStyle: AnyShapeStyle {
        if data != nil, displayMode == .fill { return AnyShapeStyle(Color.clear) }
        return AnyShapeStyle(.quaternary)
    }
}
