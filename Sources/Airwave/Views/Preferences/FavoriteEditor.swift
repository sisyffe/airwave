import SwiftUI
import UniformTypeIdentifiers

/// Detail pane for editing a single favorite in the Favorites settings tab.
/// Edits go through the library, so every list sees them at once.
struct FavoriteEditor: View {
    let favoriteID: Track.ID
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var library: TrackLibrary

    @State private var showImporter = false
    @State private var message: String?
    @State private var isDropTargeted = false
    @State private var nameDraft = ""
    @State private var urlDraft = ""
    @State private var nameError: String?

    private static let thumbnailSize: CGFloat = 72
    /// Matches `Thumbnail`'s corner radius so the drop highlight aligns.
    private static let cornerRadiusScale: CGFloat = 0.12

    private var favorite: Track { library.track(favoriteID) ?? Track(name: "", url: "") }
    private var isEditable: Bool { favorite.isFavorite }

    private var looksPlayable: Bool {
        URLValidation.httpURL(from: urlDraft) != nil
    }

    var body: some View {
        Form {
            Section {
                thumbnailSection
                TextField("Name", text: $nameDraft)
                    .onSubmit(commitName)
                    .disabled(!isEditable)
                if let nameError {
                    Label(nameError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                TextField("Link", text: $urlDraft)
                    .onSubmit { library.setURL(favoriteID, to: urlDraft) }
                    .disabled(!isEditable)
                    .help("YouTube URL or direct audio/HLS stream URL")
                if !urlDraft.isEmpty && !looksPlayable {
                    Label("This doesn't look like a supported link.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button {
                        commitName()
                        library.setURL(favoriteID, to: urlDraft)
                        Task { await player.play(id: favoriteID) }
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
                    timeRow(title: "Start offset", time: trimBinding(\.startOffset))
                    timeRow(title: "End offset", time: trimBinding(\.endOffset))
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
        .disabled(!isEditable)
        .onAppear {
            nameDraft = favorite.name
            urlDraft = favorite.url
        }
        .onDisappear { commitName() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image], onCompletion: handleImport)
    }

    private func commitName() {
        guard isEditable, nameDraft != favorite.name else { return }
        if library.renameFavorite(favoriteID, to: nameDraft) {
            nameError = nil
            nameDraft = favorite.name
        } else {
            nameError = "Another favorite already uses this name."
            nameDraft = favorite.name
        }
    }

    private func trimBinding(_ keyPath: WritableKeyPath<Track, TimeInterval?>) -> Binding<TimeInterval?> {
        Binding(
            get: { favorite[keyPath: keyPath] },
            set: { newValue in
                var updated = favorite
                updated[keyPath: keyPath] = newValue
                library.setTrim(favoriteID, start: updated.startOffset, end: updated.endOffset)
            })
    }

    private var thumbnailSection: some View {
        VStack(spacing: 6) {
            Thumbnail(data: ThumbnailStore.data(for: favorite.thumbnailKey), size: Self.thumbnailSize)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.thumbnailSize * Self.cornerRadiusScale)
                        .strokeBorder(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
                }
                .onDrop(of: [UTType.image], isTargeted: $isDropTargeted, perform: handleDrop)
            HStack(spacing: 6) {
                Button("Paste Image") { pasteThumbnail() }
                Button("Choose Image…") { showImporter = true }
            }
            .controlSize(.small)
            if favorite.hasCustomThumbnail {
                Button("Reset to default") { resetThumbnail() }
                    .controlSize(.small)
            }
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

    /// Stores the image once; every list and the player pick it up from the library.
    private func applyCustomThumbnail(_ data: Data) {
        guard let key = ThumbnailStore.save(data) else {
            message = "That doesn't look like an image."
            return
        }
        message = nil
        library.setCustomThumbnail(favoriteID, key: key)
    }

    private func resetThumbnail() {
        library.clearCustomThumbnail(favoriteID)
        message = nil
        let url = favorite.url
        guard !url.isEmpty else { return }
        Task { @MainActor in
            guard let data = await StreamResolver.thumbnail(for: url), let key = ThumbnailStore.save(data) else { return }
            library.applyThumbnail(key, forURL: url)
        }
    }
}
