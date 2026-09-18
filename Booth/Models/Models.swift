import Foundation
import SwiftUI

enum EpisodeStatus: String, Codable, CaseIterable, Identifiable {
    case draft = "Taslak"
    case recording = "Kayıt"
    case editing = "Düzenleme"
    case ready = "Hazır"

    var id: String { rawValue }
}

enum TrackKind: String, Codable, CaseIterable {
    case voice
    case music
    case sfx
    case aux

    var displayName: String {
        switch self {
        case .voice: return "Konuşma"
        case .music: return "Müzik"
        case .sfx: return "Efekt"
        case .aux: return "Katman"
        }
    }

    var hex: String {
        switch self {
        case .voice: return "5EC8C5"
        case .music: return "E8A54B"
        case .sfx: return "8B7CFF"
        case .aux: return "8C949E"
        }
    }
}

enum EQPreset: String, Codable, CaseIterable, Identifiable {
    case speech = "Konuşma"
    case radio = "Radyo"
    case flat = "Düz"

    var id: String { rawValue }

    var bass: Double {
        switch self {
        case .speech: return 1.5
        case .radio: return 3.0
        case .flat: return 0
        }
    }

    var mid: Double {
        switch self {
        case .speech: return -0.5
        case .radio: return 1.5
        case .flat: return 0
        }
    }

    var treble: Double {
        switch self {
        case .speech: return 2.0
        case .radio: return 3.5
        case .flat: return 0
        }
    }
}

enum VoiceIsolatorPreset: String, Codable, CaseIterable, Identifiable {
    case off = "Kapalı"
    case cleanVocals = "Clean Vocals"
    case lecture = "Lecture"

    var id: String { rawValue }

    var isOn: Bool { self != .off }

    var detail: String {
        switch self {
        case .off:
            return ""
        case .cleanVocals:
            return "Vokali öne alır; uğultu, oda ve nefes gürültüsünü kısar."
        case .lecture:
            return "Ders ve salon kaydı: HVAC, kalabalık ve yankıyı kesip konuşmayı netleştirir."
        }
    }
}

enum CompressorPreset: String, Codable, CaseIterable, Identifiable {
    case off = "Kapalı"
    case natural = "Doğal"
    case podcast = "Podcast"
    case broadcast = "Yayın"

    var id: String { rawValue }

    var threshold: Float {
        switch self {
        case .off: return 0
        case .natural: return -18
        case .podcast: return -22
        case .broadcast: return -26
        }
    }

    var ratio: Float {
        switch self {
        case .off: return 1
        case .natural: return 2
        case .podcast: return 4
        case .broadcast: return 8
        }
    }
}

struct Marker: Identifiable, Codable, Hashable {
    var id: UUID
    var time: TimeInterval
    var label: String

    init(id: UUID = UUID(), time: TimeInterval, label: String = "İşaret") {
        self.id = id
        self.time = time
        self.label = label
    }
}

struct MediaAsset: Identifiable, Codable, Hashable {
    var id: UUID
    var filename: String
    var displayName: String
    var duration: TimeInterval
    var kindHint: TrackKind

    init(id: UUID = UUID(), filename: String, displayName: String, duration: TimeInterval, kindHint: TrackKind) {
        self.id = id
        self.filename = filename
        self.displayName = displayName
        self.duration = duration
        self.kindHint = kindHint
    }
}

struct ClipEffects: Codable, Hashable {
    var eqEnabled: Bool = false
    var eqPreset: EQPreset = .speech
    var bass: Double = 1.5
    var mid: Double = -0.5
    var treble: Double = 2.0
    var noiseEnabled: Bool = false
    var noiseAmount: Double = 0.35
    var compressorEnabled: Bool = false
    var compressorPreset: CompressorPreset = .podcast
    var makeupGainDB: Double = 1.8
    var echoEnabled: Bool = false
    var echoAmount: Double = 0.55
    var isolatorPreset: VoiceIsolatorPreset = .off
    var isolatorAmount: Double = 0.75

    mutating func apply(preset: EQPreset) {
        eqPreset = preset
        bass = preset.bass
        mid = preset.mid
        treble = preset.treble
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eqEnabled = try container.decodeIfPresent(Bool.self, forKey: .eqEnabled) ?? false
        eqPreset = try container.decodeIfPresent(EQPreset.self, forKey: .eqPreset) ?? .speech
        bass = try container.decodeIfPresent(Double.self, forKey: .bass) ?? 1.5
        mid = try container.decodeIfPresent(Double.self, forKey: .mid) ?? -0.5
        treble = try container.decodeIfPresent(Double.self, forKey: .treble) ?? 2.0
        noiseEnabled = try container.decodeIfPresent(Bool.self, forKey: .noiseEnabled) ?? false
        noiseAmount = try container.decodeIfPresent(Double.self, forKey: .noiseAmount) ?? 0.35
        compressorEnabled = try container.decodeIfPresent(Bool.self, forKey: .compressorEnabled) ?? false
        compressorPreset = try container.decodeIfPresent(CompressorPreset.self, forKey: .compressorPreset) ?? .podcast
        makeupGainDB = try container.decodeIfPresent(Double.self, forKey: .makeupGainDB) ?? 1.8
        echoEnabled = try container.decodeIfPresent(Bool.self, forKey: .echoEnabled) ?? false
        echoAmount = try container.decodeIfPresent(Double.self, forKey: .echoAmount) ?? 0.55
        isolatorPreset = try container.decodeIfPresent(VoiceIsolatorPreset.self, forKey: .isolatorPreset) ?? .off
        isolatorAmount = try container.decodeIfPresent(Double.self, forKey: .isolatorAmount) ?? 0.75
    }
}

struct Clip: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var filename: String
    var startOnTimeline: TimeInterval
    var sourceOffset: TimeInterval
    var duration: TimeInterval
    var sourceDuration: TimeInterval
    var gainDB: Double
    var fadeIn: TimeInterval
    var fadeOut: TimeInterval
    var effects: ClipEffects

    init(
        id: UUID = UUID(),
        name: String,
        filename: String,
        startOnTimeline: TimeInterval = 0,
        sourceOffset: TimeInterval = 0,
        duration: TimeInterval,
        sourceDuration: TimeInterval,
        gainDB: Double = 0,
        fadeIn: TimeInterval = 0,
        fadeOut: TimeInterval = 0,
        effects: ClipEffects = ClipEffects()
    ) {
        self.id = id
        self.name = name
        self.filename = filename
        self.startOnTimeline = startOnTimeline
        self.sourceOffset = sourceOffset
        self.duration = duration
        self.sourceDuration = sourceDuration
        self.gainDB = gainDB
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.effects = effects
    }

    var endTime: TimeInterval { startOnTimeline + duration }

    var linearGain: Float {
        Float(pow(10.0, gainDB / 20.0))
    }
}

struct Track: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: TrackKind
    var muted: Bool
    var solo: Bool
    var volume: Double
    var clips: [Clip]

    init(
        id: UUID = UUID(),
        name: String,
        kind: TrackKind,
        muted: Bool = false,
        solo: Bool = false,
        volume: Double = 1.0,
        clips: [Clip] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.muted = muted
        self.solo = solo
        self.volume = volume
        self.clips = clips
    }

    static func template(_ kind: TrackKind, name: String? = nil) -> Track {
        Track(name: name ?? kind.displayName, kind: kind)
    }
}

struct Episode: Identifiable, Codable, Hashable {
    static let maxTracks = 6

    var id: UUID
    var title: String
    var status: EpisodeStatus
    var createdAt: Date
    var updatedAt: Date
    var tracks: [Track]
    var markers: [Marker]
    var library: [MediaAsset]

    init(
        id: UUID = UUID(),
        title: String,
        status: EpisodeStatus = .draft,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        tracks: [Track] = [
            .template(.voice),
            .template(.music),
            .template(.sfx)
        ],
        markers: [Marker] = [],
        library: [MediaAsset] = []
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tracks = tracks
        self.markers = markers
        self.library = library
    }

    var contentDuration: TimeInterval {
        tracks.flatMap(\.clips).map(\.endTime).max() ?? 0
    }

    var timelineDuration: TimeInterval {
        max(contentDuration + 15, 90)
    }

    var clipCount: Int {
        tracks.reduce(0) { $0 + $1.clips.count }
    }

    func clip(id: UUID) -> Clip? {
        tracks.flatMap(\.clips).first { $0.id == id }
    }

    func track(containing clipID: UUID) -> Track? {
        tracks.first { track in track.clips.contains { $0.id == clipID } }
    }

    mutating func updateClip(_ id: UUID, _ body: (inout Clip) -> Void) {
        for t in tracks.indices {
            if let c = tracks[t].clips.firstIndex(where: { $0.id == id }) {
                body(&tracks[t].clips[c])
                return
            }
        }
    }

    mutating func removeClip(_ id: UUID) {
        for t in tracks.indices {
            tracks[t].clips.removeAll { $0.id == id }
        }
        touch()
    }

    mutating func addClip(_ clip: Clip, to trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].clips.append(clip)
        tracks[index].clips.sort { $0.startOnTimeline < $1.startOnTimeline }
        if status == .draft { status = .editing }
        touch()
    }

    mutating func splitClip(_ id: UUID, at time: TimeInterval) {
        guard var clip = clip(id: id), time > clip.startOnTimeline + 0.05, time < clip.endTime - 0.05 else { return }
        let leftDuration = time - clip.startOnTimeline
        var right = clip
        right.id = UUID()
        right.name = clip.name + " B"
        right.startOnTimeline = time
        right.sourceOffset = clip.sourceOffset + leftDuration
        right.duration = clip.duration - leftDuration
        clip.duration = leftDuration
        updateClip(id) { $0 = clip }
        if let track = track(containing: id) {
            addClip(right, to: track.id)
        }
    }

    mutating func appendRecording(_ asset: MediaAsset, duration: TimeInterval) {
        library.append(asset)
        guard let voice = tracks.first(where: { $0.kind == .voice }) else { return }
        let start = tracks.first(where: { $0.kind == .voice })?.clips.map(\.endTime).max() ?? 0
        let clip = Clip(
            name: asset.displayName,
            filename: asset.filename,
            startOnTimeline: start,
            duration: duration,
            sourceDuration: duration
        )
        addClip(clip, to: voice.id)
        status = .editing
    }

    mutating func placeAsset(_ asset: MediaAsset, on kind: TrackKind, at time: TimeInterval) {
        let trackID: UUID
        if let existing = tracks.first(where: { $0.kind == kind }) {
            trackID = existing.id
        } else if tracks.count < Self.maxTracks {
            let track = Track.template(kind)
            tracks.append(track)
            trackID = track.id
        } else {
            trackID = tracks[0].id
        }
        let clip = Clip(
            name: asset.displayName,
            filename: asset.filename,
            startOnTimeline: max(0, time),
            duration: asset.duration,
            sourceDuration: asset.duration
        )
        addClip(clip, to: trackID)
    }

    mutating func addAuxTrack() {
        guard tracks.count < Self.maxTracks else { return }
        tracks.append(.template(.aux, name: "Katman \(tracks.count + 1)"))
        touch()
    }

    mutating func touch() {
        updatedAt = Date()
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case aac = "AAC"
    case wav = "WAV"
    case aiff = "AIFF"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .aac: return "m4a"
        case .wav: return "wav"
        case .aiff: return "aiff"
        }
    }

    var displayName: String {
        switch self {
        case .aac: return "AAC (önerilen)"
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        }
    }
}
