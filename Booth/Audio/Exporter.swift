import AVFoundation
import Foundation

enum ExporterError: LocalizedError {
    case empty
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .empty: return "Dışa aktarılacak kayıt yok."
        case .writeFailed: return "Dosya yazılamadı."
        }
    }
}

struct LoudnessReport {
    var peak: Float
    var lufs: Float
    var duration: TimeInterval
    var truePeak: Float

    var isBroadcastSafe: Bool {
        truePeak <= 0.89 && lufs <= -14 && lufs >= -20
    }
}

enum OfflineExporter {
    static let sampleRate: Double = 48_000

    static func export(
        episode: Episode,
        mediaRoot: URL,
        destination: URL,
        format: ExportFormat,
        normalize: Bool,
        progress: ((Double) -> Void)? = nil
    ) throws -> LoudnessReport {
        let duration = episode.contentDuration
        guard duration > 0.05 else { throw ExporterError.empty }

        let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let totalFrames = Int((duration * sampleRate).rounded(.up))
        let chunk = 8192

        var peak: Float = 0.0001
        var squareSum: Double = 0
        var sampleCount: Int = 0
        var voiceSquare: Double = 0
        var voiceCount: Int = 0
        var isolatorStates: [UUID: VoiceIsolator.State] = [:]
        var limiterEnv: Float = 0
        let ceiling = Float(pow(10 as Float, Float(episode.mix.limiterCeilingDB) / 20))

        func visitChunks(applyGain: Float, voiceGain: Float, writer: ((AVAudioPCMBuffer) throws -> Void)?) throws {
            isolatorStates.removeAll()
            limiterEnv = 0
            var frame = 0
            while frame < totalFrames {
                let count = min(chunk, totalFrames - frame)
                guard let mix = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: AVAudioFrameCount(count)) else { break }
                mix.frameLength = AVAudioFrameCount(count)
                guard let left = mix.floatChannelData?[0], let right = mix.floatChannelData?[1] else { break }
                for i in 0..<count {
                    left[i] = 0
                    right[i] = 0
                }
                var voice = [Float](repeating: 0, count: count)

                let startTime = Double(frame) / sampleRate
                let endTime = Double(frame + count) / sampleRate
                let anySolo = episode.tracks.contains(where: \.solo)

                for track in episode.tracks where track.kind == .voice {
                    if track.muted { continue }
                    if anySolo && !track.solo { continue }
                    for clip in track.clips {
                        guard clip.endTime > startTime, clip.startOnTimeline < endTime else { continue }
                        addClip(
                            clip,
                            track: track,
                            episode: episode,
                            mediaRoot: mediaRoot,
                            mixLeft: left,
                            mixRight: right,
                            voice: &voice,
                            mixStartFrame: frame,
                            mixCount: count,
                            applyGain: applyGain * voiceGain,
                            duck: 1,
                            isolatorStates: &isolatorStates
                        )
                    }
                }

                for track in episode.tracks where track.kind != .voice {
                    if track.muted { continue }
                    if anySolo && !track.solo { continue }
                    for clip in track.clips {
                        guard clip.endTime > startTime, clip.startOnTimeline < endTime else { continue }
                        addClip(
                            clip,
                            track: track,
                            episode: episode,
                            mediaRoot: mediaRoot,
                            mixLeft: left,
                            mixRight: right,
                            voice: &voice,
                            mixStartFrame: frame,
                            mixCount: count,
                            applyGain: applyGain,
                            duck: 1,
                            isolatorStates: &isolatorStates
                        )
                    }
                }

                for i in 0..<count {
                    if episode.mix.limiterEnabled && !episode.mix.bypassEffects {
                        left[i] = MixMath.limit(left[i], ceiling: ceiling, envelope: &limiterEnv)
                        right[i] = MixMath.limit(right[i], ceiling: ceiling, envelope: &limiterEnv)
                    }
                    peak = max(peak, abs(left[i]), abs(right[i]))
                    squareSum += Double(left[i] * left[i] + right[i] * right[i]) / 2
                    voiceSquare += Double(voice[i] * voice[i])
                    if voice[i] != 0 { voiceCount += 1 }
                }
                sampleCount += count
                if let writer {
                    try writer(mix)
                }
                frame += count
                progress?(Double(frame) / Double(totalFrames) * (writer == nil ? 0.45 : 1.0))
            }
        }

        try visitChunks(applyGain: 1, voiceGain: 1, writer: nil)

        var gain: Float = 1
        var voiceGain: Float = 1
        if normalize {
            let rms = Float(sqrt(squareSum / Double(max(sampleCount, 1))))
            let rmsDB = 20 * log10(max(rms, 0.00001))
            let peakDB = 20 * log10(max(peak, 0.00001))
            let lufsGain = pow(10, (-16 - rmsDB) / 20)
            let peakGain = pow(10, (-1.5 - peakDB) / 20)
            gain = min(lufsGain, peakGain)
        }
        if episode.mix.autoLevelEnabled {
            let voiceRMS = Float(sqrt(voiceSquare / Double(max(voiceCount, 1))))
            voiceGain = MixMath.autoLevelGain(rms: voiceRMS)
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        let settings = outputSettings(format: format, stereo: stereo)
        let outFile = try AVAudioFile(forWriting: destination, settings: settings)
        peak = 0.0001
        squareSum = 0
        sampleCount = 0
        try visitChunks(applyGain: gain, voiceGain: voiceGain) { buffer in
            try outFile.write(from: buffer)
        }

        let rms = Float(sqrt(squareSum / Double(max(sampleCount, 1))))
        let lufs = 20 * log10(max(rms, 0.00001))
        return LoudnessReport(peak: peak, lufs: lufs, duration: duration, truePeak: peak)
    }

    private static func outputSettings(format: ExportFormat, stereo: AVAudioFormat) -> [String: Any] {
        switch format {
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        case .aiff:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: true,
                AVLinearPCMIsNonInterleaved: false
            ]
        case .aac:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 256_000
            ]
        }
    }

    private static func addClip(
        _ clip: Clip,
        track: Track,
        episode: Episode,
        mediaRoot: URL,
        mixLeft: UnsafeMutablePointer<Float>,
        mixRight: UnsafeMutablePointer<Float>,
        voice: inout [Float],
        mixStartFrame: Int,
        mixCount: Int,
        applyGain: Float,
                            duck _: Float,
        isolatorStates: inout [UUID: VoiceIsolator.State]
    ) {
        let url = mediaRoot.appendingPathComponent(clip.playbackFilename)
        guard let file = try? AVAudioFile(forReading: url) else { return }
        let srcRate = file.processingFormat.sampleRate
        let channels = Int(file.processingFormat.channelCount)

        let mixStartTime = Double(mixStartFrame) / sampleRate
        let overlapStart = max(mixStartTime, clip.startOnTimeline)
        let overlapEnd = min(mixStartTime + Double(mixCount) / sampleRate, clip.endTime)
        guard overlapEnd > overlapStart else { return }

        let isolatorOn = clip.effects.isolatorPreset.isOn
        let echoDelay = (clip.effects.echoEnabled || isolatorOn) ? Int(0.034 * srcRate) : 0
        let echoDelay2 = (clip.effects.echoEnabled || isolatorOn) ? Int(0.068 * srcRate) : 0
        let extra = max(echoDelay2, echoDelay)

        let srcTime = clip.sourceOffset + (overlapStart - clip.startOnTimeline)
        let srcFrame = max(0, AVAudioFramePosition(srcTime * srcRate) - AVAudioFramePosition(extra))
        let skipped = Int(AVAudioFramePosition(srcTime * srcRate) - srcFrame)
        let framesToRead = AVAudioFrameCount(((overlapEnd - overlapStart) * srcRate).rounded(.up) + 16 + Double(extra))
        guard srcFrame < file.length else { return }

        file.framePosition = srcFrame
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: framesToRead) else { return }
        do {
            try file.read(into: srcBuffer, frameCount: min(framesToRead, AVAudioFrameCount(file.length - srcFrame)))
        } catch {
            return
        }
        guard let data = srcBuffer.floatChannelData else { return }
        let srcFrames = Int(srcBuffer.frameLength)
        let destOffset = Int(((overlapStart - mixStartTime) * sampleRate).rounded())
        let destCount = Int(((overlapEnd - overlapStart) * sampleRate).rounded())
        let clipGain = clip.linearGain * Float(track.volume) * applyGain
        let bypass = episode.mix.bypassEffects || clip.effects.bypassEffects
        var hpPrev: Float = 0
        var hpState: Float = 0
        let hpHz = clip.effects.highPassEnabled ? clip.effects.highPassHz : 0
        let hpAlpha: Float = hpHz > 20 ? Float(1 / (2 * Double.pi * hpHz) / (1 / (2 * Double.pi * hpHz) + 1 / srcRate)) : 1

        for i in 0..<destCount {
            let destIndex = destOffset + i
            guard destIndex >= 0, destIndex < mixCount else { continue }
            let srcIndex = min(srcFrames - 1, skipped + Int(Double(i) * srcRate / sampleRate))
            var sample = data[0][srcIndex]
            if channels > 1 {
                sample = (sample + data[1][srcIndex]) * 0.5
            }

            let t = overlapStart + Double(i) / sampleRate - clip.startOnTimeline
            var env: Float = 1
            if clip.fadeIn > 0, t < clip.fadeIn {
                env *= Float(t / clip.fadeIn)
            }
            if clip.fadeOut > 0, t > clip.duration - clip.fadeOut {
                env *= Float(max(0, (clip.duration - t) / clip.fadeOut))
            }

            if !bypass {
                if clip.effects.highPassEnabled {
                    hpState = hpAlpha * (hpState + sample - hpPrev)
                    hpPrev = sample
                    sample = hpState
                }
                if clip.effects.eqEnabled {
                    let tilt = Float(clip.effects.treble - clip.effects.bass) * 0.02
                    sample += sample * tilt
                    sample *= 1 + Float(clip.effects.mid) * 0.015
                }
                if clip.effects.noiseEnabled, abs(sample) < Float(0.02 + clip.effects.noiseAmount * 0.04) {
                    sample *= Float(1 - clip.effects.noiseAmount * 0.85)
                }
                if clip.effects.deEssEnabled, abs(sample) > 0.16 {
                    sample *= Float(1 - clip.effects.deEssAmount * 0.45)
                }
                if let profile = VoiceIsolator.profile(clip.effects.isolatorPreset, amount: clip.effects.isolatorAmount) {
                    func delayed(_ offset: Int) -> Float {
                        let idx = srcIndex - offset
                        guard idx >= 0, idx < srcFrames else { return 0 }
                        var value = data[0][idx]
                        if channels > 1 { value = (value + data[1][idx]) * 0.5 }
                        return value
                    }
                    var state = isolatorStates[clip.id] ?? VoiceIsolator.State()
                    sample = VoiceIsolator.process(
                        sample,
                        state: &state,
                        profile: profile,
                        delayed1: delayed(echoDelay),
                        delayed2: delayed(echoDelay2)
                    )
                    isolatorStates[clip.id] = state
                }
                if clip.effects.echoEnabled {
                    let amount = Float(clip.effects.echoAmount)
                    func delayed(_ offset: Int) -> Float {
                        let idx = srcIndex - offset
                        guard idx >= 0, idx < srcFrames else { return 0 }
                        var value = data[0][idx]
                        if channels > 1 { value = (value + data[1][idx]) * 0.5 }
                        return value
                    }
                    sample -= delayed(echoDelay) * (0.42 * amount)
                    sample -= delayed(echoDelay2) * (0.22 * amount)
                    if abs(sample) < 0.018 + amount * 0.03 {
                        sample *= 1 - amount * 0.72
                    }
                }
                if clip.effects.compressorEnabled, clip.effects.compressorPreset != .off {
                    let threshold = pow(10 as Float, clip.effects.compressorPreset.threshold / 20)
                    let magnitude = abs(sample)
                    if magnitude > threshold {
                        let compressed = threshold + (magnitude - threshold) / clip.effects.compressorPreset.ratio
                        sample = copysign(compressed, sample)
                    }
                    sample *= Float(pow(10 as Float, Float(clip.effects.makeupGainDB) / 20))
                }
            }

            var ducked: Float = 1
            if episode.mix.duckingEnabled, track.kind != .voice {
                ducked = MixMath.duckGain(voiceAmplitude: destIndex < voice.count ? abs(voice[destIndex]) : 0, amount: episode.mix.duckingAmount)
            }
            sample *= clipGain * env * ducked
            let pan = MixMath.panGains(track.pan)
            mixLeft[destIndex] += sample * pan.left
            mixRight[destIndex] += sample * pan.right
            if track.kind == .voice, destIndex < voice.count {
                voice[destIndex] += sample
            }
        }
    }
}
