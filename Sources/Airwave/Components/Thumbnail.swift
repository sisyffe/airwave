import SwiftUI
import AppKit

/// Rounded thumbnail with a music-note fallback when there is no image data.
struct Thumbnail: View {
    let key: String?
    var size: CGFloat
    @AppStorage(Prefs.thumbnailDisplayMode) private var displayMode = Prefs.defaultThumbnailDisplayMode.rawValue

    /// Fallback icon size and corner radius, as fractions of `size`.
    private static let iconScale: CGFloat = 0.4
    private static let cornerRadiusScale: CGFloat = 0.12
    /// How much the blurred backdrop is enlarged so that it covers the square.
    private static let backdropScale: CGFloat = 1.15
    private static let backdropBlurRadius: CGFloat = 12

    var body: some View {
        Group {
            if let image = ThumbnailCache.image(for: key) {
                artwork(Image(nsImage: image))
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

    @ViewBuilder
    private func artwork(_ image: Image) -> some View {
        if ThumbnailDisplayMode(rawValue: displayMode) == .fit {
            // The whole image stays visible; the blurred, enlarged copy behind it fills the rest.
            ZStack {
                image.resizable()
                    .scaledToFill()
                    .scaleEffect(Self.backdropScale)
                    .blur(radius: Self.backdropBlurRadius)
                    .clipped()
                image.resizable().scaledToFit()
            }
        } else {
            image.resizable().scaledToFill()
        }
    }
}
