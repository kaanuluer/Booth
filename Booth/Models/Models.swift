import Foundation
import SwiftUI

enum EpisodeStatus: String, Codable, CaseIterable, Identifiable {
    case draft = "Taslak"
    case recording = "Kayıt"
    case editing = "Düzenleme"
    case ready = "Hazır"
    case archived = "Arşiv"

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
    var isChapter: Bool

    init(id: UUID = UUID(), time: TimeInterval, label: String = "İşaret", isChapter: Bool = false) {
        self.id = id
        self.time = time
        self.label = label
        self.isChapter = isChapter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        time = try container.decode(TimeInterval.self, forKey: .time)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? "İşaret"
        isChapter = try container.decodeIfPresent(Bool.self, forKey: .isChapter) ?? false
    }
}

struct MixSettings: Codable, Hashable {
    var duckingEnabled: Bool = true
    var duckingAmount: Double = 0.7
    var autoLevelEnabled: Bool = true
    var limiterEnabled: Bool = true
    var limiterCeilingDB: Double = -1.0
    var crossfade: TimeInterval = 0.03
    var captureVoiceIsolation: Bool = true
    var bypassEffects: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duckingEnabled = try container.decodeIfPresent(Bool.self, forKey: .duckingEnabled) ?? true
        duckingAmount = try container.decodeIfPresent(Double.self, forKey: .duckingAmount) ?? 0.7
        autoLevelEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoLevelEnabled) ?? true
        limiterEnabled = try container.decodeIfPresent(Bool.self, forKey: .limiterEnabled) ?? true
        limiterCeilingDB = try container.decodeIfPresent(Double.self, forKey: .limiterCeilingDB) ?? -1.0
        crossfade = try container.decodeIfPresent(TimeInterval.self, forKey: .crossfade) ?? 0.03
        captureVoiceIsolation = try container.decodeIfPresent(Bool.self, forKey: .captureVoiceIsolation) ?? true
        bypassEffects = try container.decodeIfPresent(Bool.self, forKey: .bypassEffects) ?? false
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
    var highPassEnabled: Bool = false
    var highPassHz: Double = 80
    var deEssEnabled: Bool = false
    var deEssAmount: Double = 0.45
    var spectralEnhance: Bool = false
    var spectralAmount: Double = 0.7
    var bypassEffects: Bool = false

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
        highPassEnabled = try container.decodeIfPresent(Bool.self, forKey: .highPassEnabled) ?? false
        highPassHz = try container.decodeIfPresent(Double.self, forKey: .highPassHz) ?? 80
        deEssEnabled = try container.decodeIfPresent(Bool.self, forKey: .deEssEnabled) ?? false
        deEssAmount = try container.decodeIfPresent(Double.self, forKey: .deEssAmount) ?? 0.45
        spectralEnhance = try container.decodeIfPresent(Bool.self, forKey: .spectralEnhance) ?? false
        spectralAmount = try container.decodeIfPresent(Double.self, forKey: .spectralAmount) ?? 0.7
        bypassEffects = try container.decodeIfPresent(Bool.self, forKey: .bypassEffects) ?? false
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
    var enhancedFilename: String?
    var transcriptSegments: [TranscriptSegment]

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
        effects: ClipEffects = ClipEffects(),
        enhancedFilename: String? = nil,
        transcriptSegments: [TranscriptSegment] = []
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
        self.enhancedFilename = enhancedFilename
        self.transcriptSegments = transcriptSegments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        filename = try container.decode(String.self, forKey: .filename)
        startOnTimeline = try container.decode(TimeInterval.self, forKey: .startOnTimeline)
        sourceOffset = try container.decodeIfPresent(TimeInterval.self, forKey: .sourceOffset) ?? 0
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        sourceDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .sourceDuration) ?? duration
        gainDB = try container.decodeIfPresent(Double.self, forKey: .gainDB) ?? 0
        fadeIn = try container.decodeIfPresent(TimeInterval.self, forKey: .fadeIn) ?? 0
        fadeOut = try container.decodeIfPresent(TimeInterval.self, forKey: .fadeOut) ?? 0
        effects = try container.decodeIfPresent(ClipEffects.self, forKey: .effects) ?? ClipEffects()
        enhancedFilename = try container.decodeIfPresent(String.self, forKey: .enhancedFilename)
        transcriptSegments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .transcriptSegments) ?? []
    }

    var endTime: TimeInterval { startOnTimeline + duration }

    var playbackFilename: String { enhancedFilename ?? filename }

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
    var pan: Double
    var clips: [Clip]

    init(
        id: UUID = UUID(),
        name: String,
        kind: TrackKind,
        muted: Bool = false,
        solo: Bool = false,
        volume: Double = 1.0,
        pan: Double = 0,
        clips: [Clip] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.muted = muted
        self.solo = solo
        self.volume = volume
        self.pan = pan
        self.clips = clips
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(TrackKind.self, forKey: .kind)
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        solo = try container.decodeIfPresent(Bool.self, forKey: .solo) ?? false
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1
        pan = try container.decodeIfPresent(Double.self, forKey: .pan) ?? 0
        clips = try container.decodeIfPresent([Clip].self, forKey: .clips) ?? []
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
    var mix: MixSettings
    var artworkFilename: String?
    var introAssetID: UUID?
    var outroAssetID: UUID?
    var transcript: String
    var showNotes: String

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
        library: [MediaAsset] = [],
        mix: MixSettings = MixSettings(),
        artworkFilename: String? = nil,
        introAssetID: UUID? = nil,
        outroAssetID: UUID? = nil,
        transcript: String = "",
        showNotes: String = ""
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tracks = tracks
        self.markers = markers
        self.library = library
        self.mix = mix
        self.artworkFilename = artworkFilename
        self.introAssetID = introAssetID
        self.outroAssetID = outroAssetID
        self.transcript = transcript
        self.showNotes = showNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decodeIfPresent(EpisodeStatus.self, forKey: .status) ?? .draft
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        tracks = try container.decodeIfPresent([Track].self, forKey: .tracks) ?? [
            .template(.voice), .template(.music), .template(.sfx)
        ]
        markers = try container.decodeIfPresent([Marker].self, forKey: .markers) ?? []
        library = try container.decodeIfPresent([MediaAsset].self, forKey: .library) ?? []
        mix = try container.decodeIfPresent(MixSettings.self, forKey: .mix) ?? MixSettings()
        artworkFilename = try container.decodeIfPresent(String.self, forKey: .artworkFilename)
        introAssetID = try container.decodeIfPresent(UUID.self, forKey: .introAssetID)
        outroAssetID = try container.decodeIfPresent(UUID.self, forKey: .outroAssetID)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        showNotes = try container.decodeIfPresent(String.self, forKey: .showNotes) ?? ""
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

    static func normalizedTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Adsız bölüm" : trimmed
    }

    mutating func rename(to raw: String) {
        title = Self.normalizedTitle(raw)
        touch()
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

    mutating func removeClip(_ id: UUID, ripple: Bool = false) {
        guard let clip = clip(id: id), let trackIndex = tracks.firstIndex(where: { $0.clips.contains { $0.id == id } }) else { return }
        tracks[trackIndex].clips.removeAll { $0.id == id }
        if ripple {
            tracks[trackIndex].clips = MixMath.rippleShift(
                clips: tracks[trackIndex].clips,
                removedStart: clip.startOnTimeline,
                removedDuration: clip.duration
            )
        }
        touch()
    }

    mutating func trimClip(_ id: UUID, edge: TrimEdge, delta: TimeInterval) {
        updateClip(id) { clip in
            switch edge {
            case .start:
                let trim = MixMath.trimStart(
                    startOnTimeline: clip.startOnTimeline,
                    sourceOffset: clip.sourceOffset,
                    duration: clip.duration,
                    sourceDuration: clip.sourceDuration,
                    delta: delta
                )
                clip.startOnTimeline = trim.startOnTimeline
                clip.sourceOffset = trim.sourceOffset
                clip.duration = trim.duration
            case .end:
                clip.duration = MixMath.trimEnd(
                    duration: clip.duration,
                    sourceOffset: clip.sourceOffset,
                    sourceDuration: clip.sourceDuration,
                    delta: delta
                )
            }
        }
    }

    mutating func replaceClip(_ id: UUID, with regions: [MixMath.Region], nameSuffix: String = "") {
        guard let original = clip(id: id), let trackID = track(containing: id)?.id else { return }
        removeClip(id)
        for (index, region) in regions.enumerated() {
            var piece = original
            piece.id = UUID()
            piece.name = regions.count == 1 ? original.name : "\(original.name)\(nameSuffix) \(index + 1)"
            piece.startOnTimeline = original.startOnTimeline + region.start
            piece.sourceOffset = original.sourceOffset + region.start
            piece.duration = region.duration
            if mix.crossfade > 0 {
                piece.fadeIn = max(piece.fadeIn, min(mix.crossfade, piece.duration / 3))
                piece.fadeOut = max(piece.fadeOut, min(mix.crossfade, piece.duration / 3))
            }
            addClip(piece, to: trackID)
        }
    }

    mutating func applyShowTemplate() {
        if let introID = introAssetID, let asset = library.first(where: { $0.id == introID }) {
            if !hasClip(filename: asset.filename, on: .music) {
                placeAsset(asset, on: .music, at: 0)
            }
        }
        if let outroID = outroAssetID, let asset = library.first(where: { $0.id == outroID }) {
            if !hasClip(filename: asset.filename, on: .music) {
                placeAsset(asset, on: .music, at: max(contentDuration, 0.01))
            }
        }
    }

    private func hasClip(filename: String, on kind: TrackKind) -> Bool {
        tracks.first(where: { $0.kind == kind })?.clips.contains { $0.filename == filename } ?? false
    }

    mutating func addClip(_ clip: Clip, to trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        var next = clip
        if mix.crossfade > 0 {
            next.fadeIn = max(next.fadeIn, min(mix.crossfade, next.duration / 3))
            next.fadeOut = max(next.fadeOut, min(mix.crossfade, next.duration / 3))
        }
        tracks[index].clips.append(next)
        tracks[index].clips.sort { $0.startOnTimeline < $1.startOnTimeline }
        if status == .draft { status = .editing }
        touch()
    }

    mutating func moveClip(_ id: UUID, to trackID: UUID, startOnTimeline: TimeInterval? = nil) {
        guard let fromIndex = tracks.firstIndex(where: { $0.clips.contains { $0.id == id } }) else { return }
        guard let toIndex = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard let clipIndex = tracks[fromIndex].clips.firstIndex(where: { $0.id == id }) else { return }

        if fromIndex == toIndex {
            if let start = startOnTimeline {
                tracks[fromIndex].clips[clipIndex].startOnTimeline = max(0, start)
                tracks[fromIndex].clips.sort { $0.startOnTimeline < $1.startOnTimeline }
            }
            return
        }

        var clip = tracks[fromIndex].clips.remove(at: clipIndex)
        if let start = startOnTimeline {
            clip.startOnTimeline = max(0, start)
        }
        tracks[toIndex].clips.append(clip)
        tracks[toIndex].clips.sort { $0.startOnTimeline < $1.startOnTimeline }
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

    mutating func appendRecording(_ asset: MediaAsset, duration: TimeInterval, at time: TimeInterval? = nil, punch: Bool = false) {
        library.append(asset)
        guard let voice = tracks.first(where: { $0.kind == .voice }) else { return }
        let start = time ?? (tracks.first(where: { $0.kind == .voice })?.clips.map(\.endTime).max() ?? 0)
        let clip = Clip(
            name: asset.displayName,
            filename: asset.filename,
            startOnTimeline: max(0, start),
            duration: duration,
            sourceDuration: duration
        )
        if punch, let index = tracks.firstIndex(where: { $0.kind == .voice }) {
            tracks[index].clips = MixMath.punchReplace(clips: tracks[index].clips, punch: clip)
            status = .editing
            touch()
            return
        }
        addClip(clip, to: voice.id)
        status = .editing
    }

    mutating func applyTranscript(clipID: UUID, text: String, segments: [TranscriptSegment]) {
        updateClip(clipID) { $0.transcriptSegments = segments }
        if transcript.isEmpty {
            transcript = text
        } else if !transcript.contains(text) {
            transcript += "\n\n" + text
        }
        if showNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showNotes = SpeechTranscriber.showNotes(title: title, transcript: transcript, chapters: markers)
        }
        touch()
    }

    mutating func stripFillers(clipID: UUID) {
        guard let clip = clip(id: clipID) else { return }
        let cuts = clip.transcriptSegments.filter(\.isFiller).compactMap { segment -> MixMath.Region? in
            let start = segment.start - clip.sourceOffset
            let end = start + segment.duration
            let clampedStart = max(0, start)
            let clampedEnd = min(clip.duration, end)
            guard clampedEnd - clampedStart > 0.04 else { return nil }
            return MixMath.Region(start: clampedStart, duration: clampedEnd - clampedStart)
        }
        let keep = MixMath.invertCuts(duration: clip.duration, cuts: cuts)
        guard !keep.isEmpty, keep != [MixMath.Region(start: 0, duration: clip.duration)] else { return }
        replaceClip(clipID, with: keep, nameSuffix: " ·")
    }

    mutating func archive(_ on: Bool) {
        status = on ? .archived : (contentDuration > 0.2 ? .editing : .draft)
        touch()
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

    mutating func sanitizeMediaNames() {
        for t in tracks.indices {
            for c in tracks[t].clips.indices {
                if let name = MediaPath.leafName(tracks[t].clips[c].filename) {
                    tracks[t].clips[c].filename = name
                }
                if let enhanced = tracks[t].clips[c].enhancedFilename {
                    tracks[t].clips[c].enhancedFilename = MediaPath.leafName(enhanced)
                }
            }
        }
        if let artworkFilename {
            self.artworkFilename = MediaPath.leafName(artworkFilename)
        }
        library = library.compactMap { asset in
            guard let name = MediaPath.leafName(asset.filename) else { return nil }
            var next = asset
            next.filename = name
            return next
        }
    }
}

enum TrimEdge {
    case start
    case end
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
