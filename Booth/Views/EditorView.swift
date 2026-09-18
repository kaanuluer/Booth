import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @Binding var episode: Episode
    @EnvironmentObject private var store: EpisodeStore
    @StateObject private var mixer = MixerEngine()
    @State private var selectedClipID: UUID?
    @State private var pixelsPerSecond: CGFloat = 36
    @State private var snapEnabled = true
    @State private var showRecord = false
    @State private var punchIn = false
    @State private var punchAt: TimeInterval = 0
    @State private var showExport = false
    @State private var showNotes = false
    @State private var isImporting = false
    @State private var libraryCollapsed = false
    @State private var importKind: TrackKind = .music

    var body: some View {
        ZStack {
            BoothTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                TransportBar(
                    episode: $episode,
                    mixer: mixer,
                    snapEnabled: $snapEnabled,
                    pixelsPerSecond: $pixelsPerSecond,
                    mediaRoot: store.mediaDirectory(episode),
                    onRecord: {
                        punchIn = false
                        punchAt = 0
                        showRecord = true
                    },
                    onPunch: {
                        punchIn = true
                        punchAt = mixer.playhead
                        showRecord = true
                    },
                    onNotes: { showNotes = true },
                    onExport: { showExport = true }
                )
                Divider().background(BoothTheme.hairline)
                HStack(spacing: 0) {
                    if !libraryCollapsed {
                        ClipLibraryPanel(
                            episode: $episode,
                            selectedClipID: $selectedClipID,
                            onImport: { isImporting = true },
                            onPlace: { asset in
                                store.checkpoint(episode)
                                episode.placeAsset(asset, on: asset.kindHint, at: mixer.playhead)
                            }
                        )
                        .frame(width: 280)
                        Divider().background(BoothTheme.hairline)
                    }
                    TimelineView(
                        episode: $episode,
                        selectedClipID: $selectedClipID,
                        playhead: $mixer.playhead,
                        pixelsPerSecond: pixelsPerSecond,
                        snapEnabled: snapEnabled,
                        mediaRoot: store.mediaDirectory(episode),
                        onSeek: { mixer.seek($0, episode: episode, mediaRoot: store.mediaDirectory(episode)) },
                        onCheckpoint: { store.checkpoint(episode) }
                    )
                    if let clipID = selectedClipID, episode.clip(id: clipID) != nil {
                        Divider().background(BoothTheme.hairline)
                        InspectorPanel(
                            episode: $episode,
                            clipID: clipID,
                            playhead: mixer.playhead,
                            mediaRoot: store.mediaDirectory(episode)
                        )
                        .environmentObject(store)
                        .frame(width: 320)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(false)
        .toolbarBackground(BoothTheme.canvas, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(isPresented: $showRecord) {
            RecordView(episode: $episode, punchIn: punchIn, punchAt: punchAt)
                .environmentObject(store)
        }
        .sheet(isPresented: $showNotes) {
            TranscriptNotesView(episode: $episode, mediaRoot: store.mediaDirectory(episode))
                .environmentObject(store)
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(episode: $episode)
                .environmentObject(store)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .onDisappear {
            mixer.stop()
            store.save(episode, persistImmediately: true)
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            do {
                store.checkpoint(episode)
                let asset = try store.importFile(from: url, into: episode, kind: importKind)
                episode.library.append(asset)
                episode.placeAsset(asset, on: asset.kindHint, at: mixer.playhead)
            } catch {
                print(error)
            }
        }
        store.save(episode)
    }
}

struct TransportBar: View {
    @Binding var episode: Episode
    @ObservedObject var mixer: MixerEngine
    @Binding var snapEnabled: Bool
    @Binding var pixelsPerSecond: CGFloat
    var mediaRoot: URL
    var onRecord: () -> Void
    var onPunch: () -> Void
    var onNotes: () -> Void
    var onExport: () -> Void
    @FocusState private var titleFocused: Bool
    @EnvironmentObject private var store: EpisodeStore

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BoothTheme.secondary)
                TextField("Bölüm adı", text: $episode.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BoothTheme.text)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($titleFocused)
                    .onSubmit { episode.rename(to: episode.title) }
                    .onChange(of: titleFocused) { _, focused in
                        if !focused { episode.rename(to: episode.title) }
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(BoothTheme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: 280, alignment: .leading)

            HStack(spacing: 10) {
                Button { mixer.skip(-15, episode: episode, mediaRoot: mediaRoot) } label: {
                    Image(systemName: "gobackward.15")
                }
                Button { mixer.toggle(episode: episode, mediaRoot: mediaRoot) } label: {
                    Image(systemName: mixer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(BoothTheme.elevated, in: Circle())
                }
                Button { mixer.skip(15, episode: episode, mediaRoot: mediaRoot) } label: {
                    Image(systemName: "goforward.15")
                }
            }
            .foregroundStyle(BoothTheme.text)

            Text("\(TimeCode.format(mixer.playhead))  /  \(TimeCode.format(episode.contentDuration))")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(BoothTheme.text)

            Button {
                if let restored = store.undo(for: episode.id) {
                    episode = restored
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!(store.undoAvailable[episode.id] ?? false))
            .keyboardShortcut("z", modifiers: .command)

            Button {
                if let restored = store.redo(for: episode.id) {
                    episode = restored
                }
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!(store.redoAvailable[episode.id] ?? false))
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Toggle("A/B", isOn: $episode.mix.bypassEffects)
                .toggleStyle(.button)
                .tint(episode.mix.bypassEffects ? BoothTheme.accent : BoothTheme.secondary)
                .font(.system(size: 12, weight: .semibold))

            Button {
                snapEnabled.toggle()
            } label: {
                Label("Yapışma", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(snapEnabled ? BoothTheme.voice : BoothTheme.secondary)
            }

            Slider(value: $pixelsPerSecond, in: 16...90)
                .frame(width: 120)

            Spacer()

            Button(action: onRecord) {
                Label("Kayıt", systemImage: "record.circle")
            }
            .buttonStyle(BoothButtonStyle())

            Button(action: onPunch) {
                Label("Punch-in", systemImage: "arrow.uturn.left")
            }
            .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))

            Button(action: onNotes) {
                Label("Notlar", systemImage: "text.alignleft")
            }
            .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))

            Button(action: onExport) {
                Label("Yayına hazırla", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(BoothButtonStyle(fill: BoothTheme.success.opacity(0.85)))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(BoothTheme.surface)
    }
}

struct ClipLibraryPanel: View {
    @Binding var episode: Episode
    @Binding var selectedClipID: UUID?
    var onImport: () -> Void
    var onPlace: (MediaAsset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Klipler")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(BoothTheme.text)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(TrackKind.allCases.filter { $0 != .aux }, id: \.self) { kind in
                        let items = episode.library.filter { $0.kindHint == kind }
                        if !items.isEmpty {
                            Text(kind.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BoothTheme.trackColor(kind))
                            ForEach(items) { asset in
                                Button {
                                    onPlace(asset)
                                } label: {
                                    HStack {
                                        Circle().fill(BoothTheme.trackColor(kind)).frame(width: 8, height: 8)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(asset.displayName)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(BoothTheme.text)
                                                .lineLimit(1)
                                            Text(TimeCode.short(asset.duration))
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(BoothTheme.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus")
                                            .foregroundStyle(BoothTheme.secondary)
                                    }
                                    .padding(10)
                                    .background(BoothTheme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            Button(action: onImport) {
                Label("Ses ekle", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
        }
        .padding(16)
        .background(BoothTheme.surface)
    }
}
