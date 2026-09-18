import Foundation
import AVFoundation
import SwiftUI

@MainActor
final class EpisodeStore: ObservableObject {
    @Published var episodes: [Episode] = []

    private let fileManager = FileManager.default

    var rootURL: URL {
        Self.rootURL
    }

    static var rootURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Booth", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func mediaURL(episodeID: UUID, filename: String) -> URL {
        rootURL
            .appendingPathComponent(episodeID.uuidString, isDirectory: true)
            .appendingPathComponent("media", isDirectory: true)
            .appendingPathComponent(filename)
    }

    init() {
        load()
    }

    func episodeDirectory(_ episode: Episode) -> URL {
        let url = rootURL.appendingPathComponent(episode.id.uuidString, isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    func mediaDirectory(_ episode: Episode) -> URL {
        let url = episodeDirectory(episode).appendingPathComponent("media", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    func mediaURL(for episode: Episode, filename: String) -> URL {
        mediaDirectory(episode).appendingPathComponent(filename)
    }

    func load() {
        guard let ids = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else {
            episodes = []
            return
        }
        var loaded: [Episode] = []
        for folder in ids where folder.hasDirectoryPath {
            let json = folder.appendingPathComponent("episode.json")
            guard let data = try? Data(contentsOf: json),
                  let episode = try? JSONDecoder().decode(Episode.self, from: data) else { continue }
            loaded.append(episode)
        }
        episodes = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var persistTasks: [UUID: Task<Void, Never>] = [:]

    func save(_ episode: Episode, persistImmediately: Bool = false) {
        if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
            if episodes[index] == episode { return }
            episodes[index] = episode
        } else {
            episodes.insert(episode, at: 0)
        }
        if persistImmediately {
            persistTasks[episode.id]?.cancel()
            writeToDisk(episode)
        } else {
            schedulePersist(episode)
        }
    }

    func binding(for id: UUID) -> Binding<Episode> {
        Binding(
            get: {
                self.episodes.first(where: { $0.id == id }) ?? Episode(title: "Bölüm")
            },
            set: { newValue in
                self.save(newValue)
            }
        )
    }

    private func schedulePersist(_ episode: Episode) {
        persistTasks[episode.id]?.cancel()
        persistTasks[episode.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.writeToDisk(episode)
            self?.persistTasks[episode.id] = nil
        }
    }

    private func writeToDisk(_ episode: Episode) {
        var snapshot = episode
        snapshot.touch()
        let url = episodeDirectory(episode).appendingPathComponent("episode.json")
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Booth save error: \(error)")
        }
    }

    func suggestedTitle() -> String {
        String(format: "S01E%02d", episodes.count + 1)
    }

    func createEpisode(title: String? = nil) -> Episode {
        let name = Episode.normalizedTitle(title ?? suggestedTitle())
        let episode = Episode(title: name)
        save(episode, persistImmediately: true)
        return episode
    }

    func rename(_ episode: Episode, to title: String) {
        var updated = episode
        updated.rename(to: title)
        save(updated, persistImmediately: true)
    }

    func delete(_ episode: Episode) {
        episodes.removeAll { $0.id == episode.id }
        try? fileManager.removeItem(at: episodeDirectory(episode))
    }

    func uniqueFilename(in episode: Episode, preferred: String) -> String {
        let ext = (preferred as NSString).pathExtension.isEmpty ? "m4a" : (preferred as NSString).pathExtension
        let base = ((preferred as NSString).deletingPathExtension as NSString).lastPathComponent
            .replacingOccurrences(of: " ", with: "-")
        var name = "\(base).\(ext)"
        var i = 2
        while fileManager.fileExists(atPath: mediaURL(for: episode, filename: name).path) {
            name = "\(base)-\(i).\(ext)"
            i += 1
        }
        return name
    }

    func importFile(from source: URL, into episode: Episode, kind: TrackKind) throws -> MediaAsset {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let filename = uniqueFilename(in: episode, preferred: source.lastPathComponent)
        let dest = mediaURL(for: episode, filename: filename)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.copyItem(at: source, to: dest)
        let duration = AudioFileInfo.duration(url: dest)
        return MediaAsset(
            filename: filename,
            displayName: (source.lastPathComponent as NSString).deletingPathExtension,
            duration: duration,
            kindHint: kind
        )
    }
}

enum AudioFileInfo {
    static func duration(url: URL) -> TimeInterval {
        if let file = try? AVAudioFile(forReading: url) {
            return Double(file.length) / file.processingFormat.sampleRate
        }
        let asset = AVURLAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }
}
