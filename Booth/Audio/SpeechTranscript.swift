import Foundation
import Speech

struct TranscriptSegment: Identifiable, Codable, Hashable {
    var id: UUID
    var text: String
    var start: TimeInterval
    var duration: TimeInterval

    init(id: UUID = UUID(), text: String, start: TimeInterval, duration: TimeInterval) {
        self.id = id
        self.text = text
        self.start = start
        self.duration = duration
    }

    var end: TimeInterval { start + duration }
    var isFiller: Bool { FillerLexicon.isFiller(text) }
}

enum FillerLexicon {
    static let words: Set<String> = [
        "şey", "yani", "işte", "hani", "ıı", "ııı", "ee", "eee", "hmm", "hm", "äh",
        "uh", "um", "uhh", "umm", "er", "ah", "eh", "falan", "filan", "aaa", "eee"
    ]

    static func isFiller(_ raw: String) -> Bool {
        let trimmed = raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !trimmed.isEmpty else { return false }
        if words.contains(trimmed) { return true }
        let folded = trimmed.folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr"))
        return words.contains(folded)
    }
}

enum SpeechTranscriber {
    enum Failure: LocalizedError {
        case unavailable
        case denied
        case empty

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Bu iPad’de konuşma tanıma yok."
            case .denied: return "Konuşma tanıma izni verilmedi."
            case .empty: return "Konuşma bulunamadı."
            }
        }
    }

    static func transcribe(url: URL) async throws -> (text: String, segments: [TranscriptSegment]) {
        let allowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard allowed else { throw Failure.denied }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR")) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { throw Failure.unavailable }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        #if !targetEnvironment(simulator)
        request.requiresOnDeviceRecognition = true
        #endif

        return try await withCheckedThrowingContinuation { continuation in
            let box = ResumeBox()
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    box.resume { continuation.resume(throwing: error) }
                    return
                }
                guard let result, result.isFinal else { return }
                let segments = result.bestTranscription.segments.map { segment in
                    TranscriptSegment(
                        text: segment.substring,
                        start: segment.timestamp,
                        duration: segment.duration
                    )
                }
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    box.resume { continuation.resume(throwing: Failure.empty) }
                } else {
                    box.resume { continuation.resume(returning: (text, segments)) }
                }
            }
        }
    }

    static func showNotes(title: String, transcript: String, chapters: [Marker]) -> String {
        var lines: [String] = [title, ""]
        let chapterList = chapters.filter(\.isChapter).sorted { $0.time < $1.time }
        if !chapterList.isEmpty {
            lines.append("Bölümler")
            for chapter in chapterList {
                lines.append("• \(TimeCode.format(chapter.time)) — \(chapter.label)")
            }
            lines.append("")
        }
        let compact = transcript
            .replacingOccurrences(of: "\n+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !compact.isEmpty {
            lines.append("Özet")
            let sentences = compact.split(whereSeparator: { ".!?".contains($0) }).map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { $0.count > 12 }
            for sentence in sentences.prefix(4) {
                lines.append("• \(sentence).")
            }
            if sentences.isEmpty {
                lines.append(String(compact.prefix(280)))
            }
        }
        return lines.joined(separator: "\n")
    }
}

private final class ResumeBox: @unchecked Sendable {
    private var resumed = false
    private let lock = NSLock()

    func resume(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        body()
    }
}
