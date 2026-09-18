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
            mixer.shutdown()
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
                print("Booth import error")
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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
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
                .padding(.vertical, 7)
                .background(BoothTheme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: 240, alignment: .leading)

                HStack(spacing: 8) {
                    Button { mixer.skip(-15, episode: episode, mediaRoot: mediaRoot) } label: {
                        Image(systemName: "gobackward.15")
                    }
                    Button { mixer.toggle(episode: episode, mediaRoot: mediaRoot) } label: {
                        Image(systemName: mixer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 40, height: 40)
                            .background(BoothTheme.elevated, in: Circle())
                    }
                    Button { mixer.skip(15, episode: episode, mediaRoot: mediaRoot) } label: {
                        Image(systemName: "goforward.15")
                    }
                }
                .foregroundStyle(BoothTheme.text)

                Text("\(TimeCode.format(mixer.playhead))  /  \(TimeCode.format(episode.contentDuration))")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(BoothTheme.text)
                    .monospacedDigit()
                    .transaction { $0.animation = nil }

                BoothIconButton(systemName: "arrow.uturn.backward", action: {
                    if let restored = store.undo(for: episode.id) { episode = restored }
                })
                .disabled(!(store.undoAvailable[episode.id] ?? false))
                .keyboardShortcut("z", modifiers: .command)

                BoothIconButton(systemName: "arrow.uturn.forward", action: {
                    if let restored = store.redo(for: episode.id) { episode = restored }
                })
                .disabled(!(store.redoAvailable[episode.id] ?? false))
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Spacer(minLength: 8)

                Button(action: onRecord) {
                    Label("Kayıt", systemImage: "record.circle")
                }
                .buttonStyle(BoothButtonStyle(compact: true))

                Button(action: onPunch) {
                    Label("Punch", systemImage: "arrow.uturn.left")
                }
                .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text, compact: true))

                Button(action: onNotes) {
                    Label("Notlar", systemImage: "text.alignleft")
                }
                .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text, compact: true))

                Button(action: onExport) {
                    Label("Yayın", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(BoothButtonStyle(fill: BoothTheme.success.opacity(0.85), compact: true))
            }

            HStack(spacing: 10) {
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

                HStack(spacing: 6) {
                    Image(systemName: "minus.magnifyingglass")
                        .foregroundStyle(BoothTheme.secondary)
                        .font(.system(size: 11))
                    Slider(value: $pixelsPerSecond, in: 16...90)
                        .frame(width: 110)
                    Image(systemName: "plus.magnifyingglass")
                        .foregroundStyle(BoothTheme.secondary)
                        .font(.system(size: 11))
                }

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BoothTheme.text)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
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
