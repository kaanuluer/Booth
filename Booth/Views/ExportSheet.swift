import SwiftUI
import PhotosUI
import UIKit

struct ExportSheet: View {
    @Binding var episode: Episode
    @EnvironmentObject private var store: EpisodeStore
    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportFormat = .aac
    @State private var normalize = true
    @State private var filename: String = ""
    @State private var isExporting = false
    @State private var progress: Double = 0
    @State private var report: LoudnessReport?
    @State private var exportedURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?
    @State private var artworkItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Tüm katmanlar tek dosyada birleşir.")
                    .foregroundStyle(BoothTheme.secondary)

                HStack {
                    metric("Süre", TimeCode.format(episode.contentDuration))
                    metric("Klip", "\(episode.clipCount)")
                    if let report {
                        metric("LUFS", String(format: "%.1f", report.lufs))
                        metric("TP", String(format: "%.2f", report.truePeak))
                    }
                }

                Picker("Format", selection: $format) {
                    ForEach(ExportFormat.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Podcast seviyesi (-16 LUFS)", isOn: $normalize)
                    .tint(BoothTheme.accent)
                    .foregroundStyle(BoothTheme.text)
                Toggle("Ducking", isOn: $episode.mix.duckingEnabled)
                    .tint(BoothTheme.accent)
                    .foregroundStyle(BoothTheme.text)
                Toggle("Auto-level", isOn: $episode.mix.autoLevelEnabled)
                    .tint(BoothTheme.accent)
                    .foregroundStyle(BoothTheme.text)
                Toggle("Limiter", isOn: $episode.mix.limiterEnabled)
                    .tint(BoothTheme.accent)
                    .foregroundStyle(BoothTheme.text)

                HStack {
                    Picker("Intro", selection: $episode.introAssetID) {
                        Text("Intro yok").tag(Optional<UUID>.none)
                        ForEach(episode.library) { asset in
                            Text(asset.displayName).tag(Optional(asset.id))
                        }
                    }
                    Picker("Outro", selection: $episode.outroAssetID) {
                        Text("Outro yok").tag(Optional<UUID>.none)
                        ForEach(episode.library) { asset in
                            Text(asset.displayName).tag(Optional(asset.id))
                        }
                    }
                }
                .foregroundStyle(BoothTheme.text)
                Button("Şablonu timeline’a yerleştir") {
                    store.checkpoint(episode)
                    episode.applyShowTemplate()
                }
                .buttonStyle(BoothButtonStyle(fill: BoothTheme.elevated, foreground: BoothTheme.text))

                PhotosPicker(selection: $artworkItem, matching: .images) {
                    Label(episode.artworkFilename == nil ? "Kapak ekle" : "Kapak seçildi", systemImage: "photo")
                }
                .onChange(of: artworkItem) { _, item in
                    Task { await importArtwork(item) }
                }

                TextField("Dosya adı", text: $filename)
                    .textFieldStyle(.roundedBorder)

                if isExporting {
                    ProgressView(value: progress)
                        .tint(BoothTheme.accent)
                }

                if let report, report.isBroadcastSafe {
                    Label("Yayına uygun", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(BoothTheme.success)
                }

                Spacer()

                Button {
                    Task { await runExport() }
                } label: {
                    Text(isExporting ? "Birleştiriliyor…" : "Dışa aktar")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BoothButtonStyle())
                .disabled(isExporting || episode.contentDuration < 0.05)
            }
            .padding(24)
            .background(BoothTheme.canvas)
            .navigationTitle("Yayına hazırla")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .onAppear {
                if filename.isEmpty {
                    filename = sanitized("\(episode.title).\(format.fileExtension)")
                }
            }
            .onChange(of: format) { _, newValue in
                filename = (filename as NSString).deletingPathExtension + "." + newValue.fileExtension
            }
            .sheet(isPresented: $showShare) {
                if let exportedURL {
                    ShareSheet(items: [exportedURL])
                }
            }
            .alert("Dışa aktarma", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(BoothTheme.secondary)
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundStyle(BoothTheme.text)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BoothTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
    }

    @MainActor
    private func runExport() async {
        isExporting = true
        progress = 0.05
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(sanitized(filename))
        let snapshot = episode
        let mediaRoot = store.mediaDirectory(episode)
        let exportFormat = format
        let shouldNormalize = normalize
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try OfflineExporter.export(
                    episode: snapshot,
                    mediaRoot: mediaRoot,
                    destination: dest,
                    format: exportFormat,
                    normalize: shouldNormalize
                ) { value in
                    Task { @MainActor in
                        progress = min(0.9, max(0.05, value))
                    }
                }
            }.value
            report = result
            exportedURL = dest
            if format == .aac {
                let artwork = episode.artworkFilename.flatMap { UIImage(contentsOfFile: store.mediaURL(for: snapshot, filename: $0).path) }
                await MediaMetadata.write(
                    to: dest,
                    title: snapshot.title,
                    artwork: artwork,
                    chapters: snapshot.markers
                )
            }
            episode.status = .ready
            if !snapshot.showNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let notesURL = dest.deletingPathExtension().appendingPathExtension("txt")
                try? snapshot.showNotes.data(using: .utf8)?.write(to: notesURL)
            }
            store.save(episode)
            if store.usingCloudFolder {
                store.publishToSyncFolder(episode)
            }
            isExporting = false
            progress = 1
            showShare = true
        } catch {
            isExporting = false
            errorMessage = error.localizedDescription
        }
    }

    private func importArtwork(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        let filename = "artwork.jpg"
        let dest = store.mediaURL(for: episode, filename: filename)
        try? data.write(to: dest)
        episode.artworkFilename = filename
        store.save(episode)
    }
}
