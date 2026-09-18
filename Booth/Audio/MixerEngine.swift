import AVFoundation
import Combine
import Foundation

@MainActor
final class MixerEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var playhead: TimeInterval = 0

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var effectNodes: [AVAudioNode] = []
    private var displayTimer: Timer?
    private var playStartedAt: TimeInterval = 0
    private var playheadAtStart: TimeInterval = 0
    private var episodeDuration: TimeInterval = 0

    func toggle(episode: Episode, mediaRoot: URL) {
        if isPlaying {
            stop()
        } else {
            play(episode: episode, mediaRoot: mediaRoot)
        }
    }

    func play(episode: Episode, mediaRoot: URL) {
        stopGraph()
        do {
            try AudioSession.configure(record: false)
        } catch {
            print("session \(error)")
        }

        episodeDuration = max(episode.contentDuration, playhead + 0.1)
        let anySolo = episode.tracks.contains(where: \.solo)
        let now = engine.outputNode.presentationLatency

        for track in episode.tracks {
            if track.muted { continue }
            if anySolo && !track.solo { continue }
            for clip in track.clips {
                guard clip.endTime > playhead else { continue }
                let url = mediaRoot.appendingPathComponent(clip.filename)
                guard FileManager.default.fileExists(atPath: url.path),
                      let file = try? AVAudioFile(forReading: url) else { continue }
                attach(clip: clip, track: track, file: file, delayCompensation: now)
            }
        }

        do {
            try engine.start()
        } catch {
            print("engine start \(error)")
            return
        }

        let hostStart = engine.outputNode.lastRenderTime ?? AVAudioTime(hostTime: mach_absolute_time())
        for player in players {
            player.play()
        }

        isPlaying = true
        playStartedAt = hostStart.seconds
        playheadAtStart = playhead
        startTimer()
        _ = hostStart
    }

    func stop() {
        displayTimer?.invalidate()
        displayTimer = nil
        isPlaying = false
        stopGraph()
    }

    func seek(_ time: TimeInterval, episode: Episode? = nil, mediaRoot: URL? = nil) {
        let wasPlaying = isPlaying
        stop()
        playhead = max(0, time)
        if wasPlaying, let episode, let mediaRoot {
            play(episode: episode, mediaRoot: mediaRoot)
        }
    }

    func skip(_ delta: TimeInterval, episode: Episode, mediaRoot: URL) {
        seek(min(max(0, playhead + delta), max(episode.contentDuration, playhead + delta)), episode: episode, mediaRoot: mediaRoot)
    }

    private func startTimer() {
        displayTimer?.invalidate()
        let origin = CACurrentMediaTime()
        let start = playhead
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.playhead = start + (CACurrentMediaTime() - origin)
                if self.playhead >= self.episodeDuration {
                    self.playhead = self.episodeDuration
                    self.stop()
                }
            }
        }
    }

    private func stopGraph() {
        players.forEach { $0.stop() }
        if engine.isRunning {
            engine.stop()
        }
        players.forEach { engine.detach($0) }
        effectNodes.forEach { engine.detach($0) }
        players.removeAll()
        effectNodes.removeAll()
        engine.reset()
    }

    private func attach(clip: Clip, track: Track, file: AVAudioFile, delayCompensation: TimeInterval) {
        let player = AVAudioPlayerNode()
        let isolatorEQ = AVAudioUnitEQ(numberOfBands: 6)
        configureIsolator(isolatorEQ, clip: clip)
        let eq = AVAudioUnitEQ(numberOfBands: 8)
        configureEQ(eq, clip: clip)
        let dynamics = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
        configureDynamics(dynamics, clip: clip)

        engine.attach(player)
        engine.attach(isolatorEQ)
        engine.attach(eq)
        engine.attach(dynamics)

        let format = file.processingFormat
        engine.connect(player, to: isolatorEQ, format: format)
        engine.connect(isolatorEQ, to: eq, format: format)
        engine.connect(eq, to: dynamics, format: format)
        engine.connect(dynamics, to: engine.mainMixerNode, format: format)

        let sampleRate = format.sampleRate
        let localOffset = max(0, playhead - clip.startOnTimeline)
        let sourceStart = min(file.length, AVAudioFramePosition((clip.sourceOffset + localOffset) * sampleRate))
        let remaining = clip.duration - localOffset
        guard remaining > 0.01 else { return }
        let frames = min(AVAudioFrameCount(remaining * sampleRate), AVAudioFrameCount(max(0, file.length - sourceStart)))
        guard frames > 0 else { return }

        let delay = max(0, clip.startOnTimeline - playhead)
        let when: AVAudioTime? = delay > 0.001
            ? AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: delay))
            : nil

        player.scheduleSegment(file, startingFrame: sourceStart, frameCount: frames, at: when)
        player.volume = clip.linearGain * Float(track.volume)
        players.append(player)
        effectNodes.append(isolatorEQ)
        effectNodes.append(eq)
        effectNodes.append(dynamics)
        _ = delayCompensation
    }

    private func configureEQ(_ eq: AVAudioUnitEQ, clip: Clip) {
        let bands = eq.bands
        func setBand(_ index: Int, type: AVAudioUnitEQFilterType, freq: Float, gain: Float, bw: Float = 1.0, bypass: Bool) {
            guard bands.indices.contains(index) else { return }
            bands[index].filterType = type
            bands[index].frequency = freq
            bands[index].bandwidth = bw
            bands[index].gain = gain
            bands[index].bypass = bypass
        }

        let eqOn = clip.effects.eqEnabled
        setBand(0, type: .parametric, freq: 120, gain: Float(clip.effects.bass), bypass: !eqOn)
        setBand(1, type: .parametric, freq: 1000, gain: Float(clip.effects.mid), bypass: !eqOn)
        setBand(2, type: .parametric, freq: 6000, gain: Float(clip.effects.treble), bypass: !eqOn)

        let noiseOn = clip.effects.noiseEnabled
        let noiseHz = Float(70 + clip.effects.noiseAmount * 140)
        setBand(3, type: .highPass, freq: noiseHz, gain: 0, bw: 0.6, bypass: !noiseOn)

        let echoOn = clip.effects.echoEnabled
        let amount = Float(clip.effects.echoAmount)
        setBand(4, type: .highPass, freq: 80 + amount * 70, gain: 0, bw: 0.7, bypass: !echoOn)
        setBand(5, type: .parametric, freq: 280, gain: -3.5 * amount, bw: 1.2, bypass: !echoOn)
        setBand(6, type: .parametric, freq: 4500, gain: -2.5 * amount, bw: 1.4, bypass: !echoOn)
        setBand(7, type: .parametric, freq: 700, gain: -2.0 * amount, bw: 0.9, bypass: !echoOn)
    }

    private func configureIsolator(_ eq: AVAudioUnitEQ, clip: Clip) {
        let bands = eq.bands
        func setBand(_ index: Int, type: AVAudioUnitEQFilterType, freq: Float, gain: Float, bw: Float = 1.0, bypass: Bool) {
            guard bands.indices.contains(index) else { return }
            bands[index].filterType = type
            bands[index].frequency = freq
            bands[index].bandwidth = bw
            bands[index].gain = gain
            bands[index].bypass = bypass
        }
        guard let profile = VoiceIsolator.profile(clip.effects.isolatorPreset, amount: clip.effects.isolatorAmount) else {
            for index in 0..<bands.count { bands[index].bypass = true }
            return
        }
        setBand(0, type: .highPass, freq: profile.highPass, gain: 0, bw: 0.7, bypass: false)
        setBand(1, type: .lowPass, freq: profile.lowPass, gain: 0, bw: 0.7, bypass: false)
        setBand(2, type: .parametric, freq: profile.mudHz, gain: profile.mudGain, bw: 1.1, bypass: false)
        setBand(3, type: .parametric, freq: profile.presenceHz, gain: profile.presenceGain, bw: 0.9, bypass: false)
        setBand(4, type: .parametric, freq: profile.deEssHz, gain: profile.deEssGain, bw: 1.2, bypass: false)
        setBand(5, type: .parametric, freq: 700, gain: profile.mudGain * 0.45, bw: 0.8, bypass: false)
    }

    private func configureDynamics(_ unit: AVAudioUnitEffect, clip: Clip) {
        let au = unit.audioUnit
        let preset = clip.effects.compressorPreset
        let compressorOn = clip.effects.compressorEnabled && preset != .off
        AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, compressorOn ? preset.threshold : 0, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, compressorOn ? 0.01 : 0.005, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, compressorOn ? 0.12 : 0.08, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, compressorOn ? Float(clip.effects.makeupGainDB) : 0, 0)

        if let isolator = VoiceIsolator.profile(clip.effects.isolatorPreset, amount: clip.effects.isolatorAmount) {
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionThreshold, kAudioUnitScope_Global, 0, isolator.expansionThreshold, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, isolator.expansionRatio, 0)
            if !compressorOn {
                AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, isolator.makeup, 0)
            }
        } else if clip.effects.echoEnabled {
            let amount = Float(clip.effects.echoAmount)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionThreshold, kAudioUnitScope_Global, 0, -42 + amount * 14, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 1.8 + amount * 6, 0)
        } else {
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 1, 0)
        }
    }
}

private extension AVAudioTime {
    var seconds: TimeInterval {
        AVAudioTime.seconds(forHostTime: hostTime)
    }
}
