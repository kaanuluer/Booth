import Foundation
import AVFoundation
import SwiftUI

@MainActor
final class EpisodeStore: ObservableObject {
    @Published var episodes: [Episode] = []
    @Published private(set) var undoAvailable: [UUID: Bool] = [:]
    @Published private(set) var redoAvailable: [UUID: Bool] = [:]

    private var undoStacks: [UUID: [Episode]] = [:]
    private var redoStacks: [UUID: [Episode]] = [:]

    private let fileManager = FileManager.default

    @Published private(set) var usingCloudFolder = false

    private static let syncBookmarkKey = "booth.syncFolder.bookmark"

    var rootURL: URL {
        Self.resolvedRoot()
    }

    static var rootURL: URL {
        resolvedRoot()
    }

    private static func documentsRoot() -> URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Booth", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        migrateLegacyIfNeeded(to: url)
        return url
    }

    private static func migrateLegacyIfNeeded(to destination: URL) {
        let marker = destination.appendingPathComponent(".migrated-from-support")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Booth", isDirectory: true)
        if let items = try? FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) {
            for item in items {
                let dest = destination.appendingPathComponent(item.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.copyItem(at: item, to: dest)
                }
            }
        }
        try? Data().write(to: marker)
    }

    private static func resolvedRoot() -> URL {
        if let cloud = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Booth", isDirectory: true) {
            try? FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
            migrateLegacyIfNeeded(to: cloud)
            return cloud
        }
        if let bookmarked = bookmarkedFolder() {
            return bookmarked
        }
        return documentsRoot()
    }

    private static func bookmarkedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: syncBookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    static func mediaURL(episodeID: UUID, filename: String) -> URL {
        rootURL
            .appendingPathComponent(episodeID.uuidString, isDirectory: true)
            .appendingPathComponent("media", isDirectory: true)
            .appendingPathComponent(filename)
    }

    init() {
        usingCloudFolder = FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
            || UserDefaults.standard.data(forKey: Self.syncBookmarkKey) != nil
        load()
    }

    func setSyncFolder(_ url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: Self.syncBookmarkKey)
        usingCloudFolder = true
        load()
    }

    func publishToSyncFolder(_ episode: Episode) {
        guard let destRoot = Self.bookmarkedFolder() ?? FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents/Booth", isDirectory: true) else { return }
        try? fileManager.createDirectory(at: destRoot, withIntermediateDirectories: true)
        let dest = destRoot.appendingPathComponent(episode.id.uuidString, isDirectory: true)
        let source = episodeDirectory(episode)
        if dest.standardizedFileURL == source.standardizedFileURL { return }
        try? fileManager.removeItem(at: dest)
        try? fileManager.copyItem(at: source, to: dest)
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
            if fileManager.isUbiquitousItem(at: json) {
                try? fileManager.startDownloadingUbiquitousItem(at: json)
            }
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

    func checkpoint(_ episode: Episode) {
        var stack = undoStacks[episode.id] ?? []
        if stack.last != episode {
            stack.append(episode)
            if stack.count > 40 { stack.removeFirst(stack.count - 40) }
            undoStacks[episode.id] = stack
            redoStacks[episode.id] = []
            publishHistory(episode.id)
        }
    }

    func undo(for id: UUID) -> Episode? {
        guard var stack = undoStacks[id], let previous = stack.popLast() else { return nil }
        undoStacks[id] = stack
        if let current = episodes.first(where: { $0.id == id }) {
            var redo = redoStacks[id] ?? []
            redo.append(current)
            redoStacks[id] = redo
        }
        publishHistory(id)
        save(previous, persistImmediately: true)
        return previous
    }

    func redo(for id: UUID) -> Episode? {
        guard var stack = redoStacks[id], let next = stack.popLast() else { return nil }
        redoStacks[id] = stack
        if let current = episodes.first(where: { $0.id == id }) {
            var undo = undoStacks[id] ?? []
            undo.append(current)
            undoStacks[id] = undo
        }
        publishHistory(id)
        save(next, persistImmediately: true)
        return next
    }

    private func publishHistory(_ id: UUID) {
        undoAvailable[id] = !(undoStacks[id] ?? []).isEmpty
        redoAvailable[id] = !(redoStacks[id] ?? []).isEmpty
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
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
