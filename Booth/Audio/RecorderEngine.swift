import AVFoundation
import Foundation

enum AudioSession {
    static func configure(record: Bool, voiceIsolation: Bool = false) throws {
        let session = AVAudioSession.sharedInstance()
        if record {
            let mode: AVAudioSession.Mode = voiceIsolation ? .voiceChat : .spokenAudio
            try session.setCategory(.playAndRecord, mode: mode, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
        } else {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.01)
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
    @Published var voiceIsolation = true
    @Published var availableInputs: [AVAudioSessionPortDescription] = []
    @Published var selectedInputUID: String?

    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var startedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var sampleRate: Double = 48_000
    private var writtenFrames: AVAudioFramePosition = 0
    private var uiTick = 0

    func start(to url: URL, voiceIsolation: Bool) throws {
        stopGraph()
        self.voiceIsolation = voiceIsolation
        try AudioSession.configure(record: true, voiceIsolation: voiceIsolation)
        refreshInputs()
        applyPreferredInput()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        #if !targetEnvironment(simulator)
        if voiceIsolation {
            try input.setVoiceProcessingEnabled(true)
            input.isVoiceProcessingAGCEnabled = false
        }
        #endif
        let format = input.inputFormat(forBus: 0)
        sampleRate = format.sampleRate == 0 ? 48_000 : format.sampleRate
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128_000
        ]
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let converterFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) ?? format

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.append(buffer: buffer, converterFormat: converterFormat)
        }

        try engine.start()
        self.engine = engine
        self.file = file
        isRecording = true
        isPaused = false
        duration = 0
        livePeaks = []
        writtenFrames = 0
        uiTick = 0
        pausedDuration = 0
        startedAt = Date()
    }

    func refreshInputs() {
        availableInputs = AVAudioSession.sharedInstance().availableInputs ?? []
        if selectedInputUID == nil {
            selectedInputUID = AVAudioSession.sharedInstance().preferredInput?.uid ?? availableInputs.first?.uid
        }
    }

    func selectInput(_ uid: String?) {
        selectedInputUID = uid
        applyPreferredInput()
    }

    private func applyPreferredInput() {
        let session = AVAudioSession.sharedInstance()
        guard let uid = selectedInputUID,
              let port = (session.availableInputs ?? []).first(where: { $0.uid == uid }) else { return }
        try? session.setPreferredInput(port)
    }

    func pause() {
        engine?.pause()
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        try? engine?.start()
        isPaused = false
    }

    @discardableResult
    func stop() -> TimeInterval {
        let length = Double(writtenFrames) / max(sampleRate, 1)
        if let url = file?.url {
            MediaPath.protect(url)
        }
        stopGraph()
        isRecording = false
        isPaused = false
        duration = length
        return length
    }

    private func stopGraph() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        file = nil
    }

    private func append(buffer: AVAudioPCMBuffer, converterFormat: AVAudioFormat) {
        if isPaused { return }
        do {
            if buffer.format.channelCount == 1 {
                try file?.write(from: buffer)
                writtenFrames += AVAudioFramePosition(buffer.frameLength)
            } else if let converted = convert(buffer, to: converterFormat) {
                try file?.write(from: converted)
                writtenFrames += AVAudioFramePosition(converted.frameLength)
            } else {
                try file?.write(from: buffer)
                writtenFrames += AVAudioFramePosition(buffer.frameLength)
            }
        } catch {
            return
        }
        let rms = rms(of: buffer)
        uiTick += 1
        guard uiTick % 3 == 0 else { return }
        Task { @MainActor in
            self.level = rms
            self.duration = Double(self.writtenFrames) / max(self.sampleRate, 1)
            self.livePeaks.append(rms)
            if self.livePeaks.count > 160 {
                self.livePeaks.removeFirst(self.livePeaks.count - 160)
            }
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format),
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameCapacity) else { return nil }
        var error: NSError?
        let input: AVAudioConverterInputBlock = { _, status in
            status.pointee = .haveData
            return buffer
        }
        converter.convert(to: out, error: &error, withInputFrom: input)
        return error == nil ? out : nil
    }

    private func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            sum += data[i] * data[i]
        }
        return min(1, sqrt(sum / Float(count)) * 4)
    }
}
