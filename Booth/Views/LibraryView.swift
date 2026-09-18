import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: EpisodeStore
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var path: [UUID] = []
    @State private var showCreate = false
    @State private var showRename = false
    @State private var draftTitle = ""
    @State private var renaming: Episode?
    @State private var deleting: Episode?
    @State private var showDelete = false
    @State private var pickingSyncFolder = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tümü"
        case draft = "Taslak"
        case ready = "Hazır"
        case archived = "Arşiv"
        var id: String { rawValue }
    }

    private var filtered: [Episode] {
        store.episodes.filter { episode in
            let matchesQuery = query.isEmpty || episode.title.localizedCaseInsensitiveContains(query)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = episode.status != .archived
            case .draft: matchesFilter = episode.status == .draft || episode.status == .editing || episode.status == .recording
            case .ready: matchesFilter = episode.status == .ready
            case .archived: matchesFilter = episode.status == .archived
            }
            return matchesQuery && matchesFilter
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                BoothTheme.canvas.ignoresSafeArea()
                HStack(spacing: 0) {
                    sidebar
                    content
                }
            }
            .navigationDestination(for: UUID.self) { id in
                EditorView(episode: store.binding(for: id))
            }
            .alert("Yeni bölüm", isPresented: $showCreate) {
                TextField("Bölüm adı", text: $draftTitle)
                Button("Oluştur") { createEpisode() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Bu ad kütüphanede ve dışa aktarılan dosyada görünür.")
            }
            .alert("Bölümü adlandır", isPresented: $showRename) {
                TextField("Bölüm adı", text: $draftTitle)
                Button("Kaydet") { commitRename() }
                Button("Vazgeç", role: .cancel) { renaming = nil }
            }
            .fileImporter(isPresented: $pickingSyncFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    try? store.setSyncFolder(url)
                }
            }
            .alert("Bölümü sil", isPresented: $showDelete) {
                Button("Sil", role: .destructive) {
                    if let deleting { store.delete(deleting) }
                    self.deleting = nil
                }
                Button("Vazgeç", role: .cancel) { deleting = nil }
            } message: {
                Text("Bu bölüm ve ses dosyaları silinir.")
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 18) {
            Text("B")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(BoothTheme.text)
                .frame(width: 44, height: 44)
                .background(BoothTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer()
        }
        .padding(.vertical, 24)
        .frame(width: 72)
        .background(BoothTheme.surface)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bölümler")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(BoothTheme.text)
                    Text("Kaydet, yerleştir, yayına hazırla.")
                        .font(.system(size: 16))
                        .foregroundStyle(BoothTheme.secondary)
                }
                Spacer()
                Button {
                    beginCreate()
                } label: {
                    Label("Yeni bölüm", systemImage: "plus")
                }
                .buttonStyle(BoothButtonStyle())
                Button {
                    pickingSyncFolder = true
                } label: {
                    Image(systemName: store.usingCloudFolder ? "icloud.fill" : "icloud")
                }
                .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))
                .accessibilityLabel("iCloud klasörü")
            }

            HStack {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(BoothTheme.secondary)
                    TextField("Bölüm ara", text: $query)
                        .textFieldStyle(.plain)
                        .foregroundStyle(BoothTheme.text)
                }
                .padding(10)
                .background(BoothTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: 320)

                Spacer()

                HStack(spacing: 4) {
                    ForEach(Filter.allCases) { item in
                        Button(item.rawValue) { filter = item }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(filter == item ? BoothTheme.text : BoothTheme.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(filter == item ? BoothTheme.elevated : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(4)
                .background(BoothTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(filtered) { episode in
                        EpisodeCard(
                            episode: episode,
                            onOpen: { path.append(episode.id) },
                            onRename: { beginRename(episode) },
                            onDelete: {
                                deleting = episode
                                showDelete = true
                            },
                            onArchive: {
                                var next = episode
                                next.archive(episode.status != .archived)
                                store.save(next, persistImmediately: true)
                                if store.usingCloudFolder {
                                    store.publishToSyncFolder(next)
                                }
                            }
                        )
                    }
                    newCard
                }
                .padding(.bottom, 24)
            }
        }
        .padding(28)
    }

    private var newCard: some View {
        Button {
            beginCreate()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(BoothTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(BoothTheme.elevated, in: Circle())
                Text("Yeni bölüm oluştur")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BoothTheme.text)
                Text("Kayıt başlatın veya hazır bir ses dosyasını içe aktarın.")
                    .font(.system(size: 13))
                    .foregroundStyle(BoothTheme.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    .foregroundStyle(BoothTheme.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    private func beginCreate() {
        draftTitle = store.suggestedTitle()
        showCreate = true
    }

    private func createEpisode() {
        let episode = store.createEpisode(title: draftTitle)
        path.append(episode.id)
    }

    private func beginRename(_ episode: Episode) {
        renaming = episode
        draftTitle = episode.title
        showRename = true
    }

    private func commitRename() {
        guard let renaming else { return }
        store.rename(renaming, to: draftTitle)
        self.renaming = nil
    }
}

struct EpisodeCard: View {
    let episode: Episode
    var onOpen: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void
    var onArchive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                BoothTheme.elevated
                if let clip = episode.tracks.first(where: { $0.kind == .voice })?.clips.first {
                    FileWaveform(
                        url: EpisodeStore.mediaURL(episodeID: episode.id, filename: clip.filename),
                        color: BoothTheme.voice,
                        barCount: 48
                    )
                    .padding(16)
                } else {
                    WaveformView(samples: [0.18, 0.32, 0.22, 0.4, 0.3, 0.2, 0.28], color: BoothTheme.voice)
                        .padding(16)
                }
            }
            .frame(height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                statusPill
                Spacer()
                Text(episode.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(BoothTheme.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                Text(episode.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BoothTheme.text)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BoothTheme.secondary)
                        .frame(width: 32, height: 32)
                        .background(BoothTheme.elevated, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bölümü adlandır")
            }

            HStack {
                Text(TimeCode.short(episode.contentDuration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(BoothTheme.secondary)
                Spacer()
                Button("Devam et", action: onOpen)
                    .buttonStyle(BoothButtonStyle())
            }
        }
        .padding(16)
        .background(BoothTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(BoothTheme.hairline, lineWidth: 1)
        )
        .contextMenu {
            Button("Aç", action: onOpen)
            Button("Yeniden adlandır", action: onRename)
            Button(episode.status == .archived ? "Arşivden çıkar" : "Arşivle", action: onArchive)
            Button("Sil", role: .destructive, action: onDelete)
        }
    }

    private var statusPill: some View {
        Text(episode.status.rawValue)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.14), in: Capsule())
    }

    private var statusColor: Color {
        switch episode.status {
        case .ready: return BoothTheme.success
        case .editing, .recording: return BoothTheme.voice
        case .draft: return BoothTheme.music
        case .archived: return BoothTheme.secondary
        }
    }
}
