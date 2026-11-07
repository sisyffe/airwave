import SwiftUI
import UniformTypeIdentifiers

/// Detail pane for editing a single favorite in the Favorites settings tab.
struct FavoriteEditor: View {
    @Binding var favorite: Favorite
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var recents: RecentsStore

    @State private var showImporter = false
    /// The name being typed. It is committed on submit or focus loss, once it is unique.
    @State private var draftName = ""
    @State private var nameWarning: String?
    @FocusState private var isNameFocused: Bool
    @State private var message: String?
    @State private var isDropTargeted = false

    private static let thumbnailSize: CGFloat = 72
    /// Matches `Thumbnail`'s corner radius so the drop highlight aligns.
    private static let cornerRadiusScale: CGFloat = 0.12

    private var looksPlayable: Bool {
        URLValidation.httpURL(from: favorite.url) != nil
    }

    var body: some View {
        Form {
            Section {
                thumbnailSection
                TextField("Name", text: $draftName)
                    .focused($isNameFocused)
                    .onSubmit(commitName)
                    .onChange(of: isNameFocused) { focused in
                        if !focused { commitName() }
                    }
                    .onChange(of: favorite.id) { _ in draftName = favorite.name }
                    .task { draftName = favorite.name }
                if let nameWarning {
                    Label(nameWarning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                TextField("Link", text: $favorite.url)
                    .help("YouTube URL or direct audio/HLS stream URL")
                if !favorite.url.isEmpty && !looksPlayable {
                    Label("This doesn't look like a supported link.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button {
                        Task { await player.play(PlaybackRequest(favorite: favorite)) }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .disabled(!looksPlayable)
                }
            } footer: {
                // Trim only applies to finite tracks, so it appears once playback
                // has confirmed the track has an end.
                if favorite.isFinite != true {
                    Text("Trimming options appear for finite tracks if they have been played at least once.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if favorite.isFinite == true {
                Section {
                    timeRow(title: "Start offset", time: $favorite.startOffset)
                    timeRow(title: "End offset", time: $favorite.endOffset)
                } header: {
                    Text("Trim")
                } footer: {
                    Text("Applies on reload. End offset is counted back from the end.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image], onCompletion: handleImport)
    }

    private var thumbnailSection: some View {
        VStack(spacing: 6) {
            Thumbnail(key: favorite.thumbnailKey, size: Self.thumbnailSize)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.thumbnailSize * Self.cornerRadiusScale)
                        .strokeBorder(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
                }
                .onDrop(of: [UTType.image], isTargeted: $isDropTargeted, perform: handleDrop)
            HStack(spacing: 6) {
                Text("Custom thumbnail:").font(.caption).foregroundStyle(.secondary)
                Button {
                    pasteThumbnail()
                } label: {
                    Label("Import", systemImage: "doc.on.clipboard")
                }
                .help("Use the image on the clipboard")
                Button {
                    showImporter = true
                } label: {
                    Label("Import", systemImage: "folder")
                }
                .help("Choose an image file")
                if favorite.hasCustomThumbnail == true {
                    Button(role: .destructive) {
                        resetThumbnail()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete the custom thumbnail and fetch the automatic one")
                }
            }
            .controlSize(.small)
            if let message {
                Text(message).font(.caption2).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func timeRow(title: String, time: Binding<TimeInterval?>) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Spacer()
            IntegerField(value: minutesBinding(time), range: 0...999)
            Text("min")
                .font(.caption2)
                .foregroundStyle(.secondary)
            IntegerField(value: secondsBinding(time), range: 0...59)
            Text("s")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func minutesBinding(_ time: Binding<TimeInterval?>) -> Binding<Int> {
        Binding(
            get: { Int(time.wrappedValue ?? 0) / 60 },
            set: { setTime(time, minutes: max(0, $0), seconds: Int(time.wrappedValue ?? 0) % 60) }
        )
    }

    private func secondsBinding(_ time: Binding<TimeInterval?>) -> Binding<Int> {
        Binding(
            get: { Int(time.wrappedValue ?? 0) % 60 },
            set: { setTime(time, minutes: Int(time.wrappedValue ?? 0) / 60, seconds: min(max($0, 0), 59)) }
        )
    }

    /// 0:00 is stored as nil (no trim).
    private func setTime(_ time: Binding<TimeInterval?>, minutes: Int, seconds: Int) {
        let total = minutes * 60 + seconds
        time.wrappedValue = total == 0 ? nil : TimeInterval(total)
    }

    /// Saves the draft name when it is unique; otherwise keeps the last valid name and says why.
    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftName = favorite.name
            nameWarning = nil
            return
        }
        guard favorites.isNameAvailable(trimmed, excluding: favorite.id) else {
            draftName = favorite.name
            nameWarning = "Another favorite already uses this name."
            return
        }
        nameWarning = nil
        favorite.name = trimmed
        draftName = trimmed
    }

    private func pasteThumbnail() {
        guard let data = Clipboard.imageData else {
            message = "No image on the clipboard."
            return
        }
        applyCustomThumbnail(data)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard let data = try? Data(contentsOf: url) else {
                message = "Couldn't read that file."
                return
            }
            applyCustomThumbnail(data)
        case .failure(let error):
            message = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard
            let provider = providers.first(where: {
                $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            })
        else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            DispatchQueue.main.async {
                guard let data else {
                    message = "Couldn't read the dropped image."
                    return
                }
                applyCustomThumbnail(data)
            }
        }
        return true
    }

    /// Applies a custom image everywhere the track appears: the favorite, its
    /// recent entry, and the Now Playing card when it is the current track.
    private func applyCustomThumbnail(_ data: Data) {
        guard let key = favorites.setCustomThumbnail(data, for: favorite.id) else {
            message = "That doesn't look like an image."
            return
        }
        message = nil
        recents.setCustomThumbnailKey(key, for: favorite.id)
        player.applyArtwork(key: key, for: favorite.url, custom: true)
    }

    private func resetThumbnail() {
        favorites.clearCustomThumbnail(for: favorite.id)
        recents.clearCustomThumbnail(for: favorite.id)
        player.applyArtwork(key: nil, for: favorite.url, custom: false)
        message = nil
        refetchThumbnail()
    }

    /// Re-fetches the automatic artwork and applies it everywhere.
    private func refetchThumbnail() {
        let url = favorite.url
        guard !url.isEmpty else { return }
        Task { @MainActor in
            guard let data = await StreamResolver.thumbnail(for: url) else { return }
            guard let key = ThumbnailCache.store(data) else { return }
            favorites.setThumbnailKey(key, for: url)
            recents.setThumbnailKey(key, for: url)
            player.applyArtwork(key: key, for: url, custom: false)
        }
    }
}
