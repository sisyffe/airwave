import SwiftUI
import AppKit

struct Thumb: View {
    let data: Data?
    var size: CGFloat
    var body: some View {
        Group {
            if let data, let img = NSImage(data: data) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
    }
}