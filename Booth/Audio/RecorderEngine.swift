import AVFoundation
import Foundation

enum AudioSession {
    static func configure(record: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if record {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        } else {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        }
        try session.setPreferredSampleRate(48_000)
        try session.setActive(true)
    }
}

@MainActor
final class RecorderEngine: ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var duration: TimeInterval = 0
    @Published var level: Float = 0
    @Published var livePeaks: [Float] = []

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt: Date?

    func start(to url: URL) throws {
        try AudioSession.configure(record: true)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128_000
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw NSError(domain: "Booth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Kayıt başlatılamadı."])
        }
        self.recorder = recorder
        isRecording = true
        isPaused = false
        duration = 0
        livePeaks = []
        startedAt = Date()
        startMeter()
    }

    func pause() {
        recorder?.pause()
        isPaused = true
        timer?.invalidate()
    }

    func resume() {
        guard isPaused else { return }
        recorder?.record()
        isPaused = false
        startMeter()
    }

    @discardableResult
    func stop() -> TimeInterval {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        let recorded = recorder?.url
        let length = recorded.flatMap { AudioFileInfo.duration(url: $0) } ?? duration
        recorder = nil
        isRecording = false
        isPaused = false
        duration = length
        return length
    }

    private func startMeter() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let recorder else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let linear = max(0, min(1, (db + 50) / 50))
        level = linear
        duration = recorder.currentTime
        livePeaks.append(linear)
        if livePeaks.count > 240 {
            livePeaks.removeFirst(livePeaks.count - 240)
        }
    }
}
