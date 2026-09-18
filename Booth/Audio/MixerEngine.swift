import AVFoundation
import Combine
import Foundation
import QuartzCore

@MainActor
final class MixerEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var playhead: TimeInterval = 0

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var effectNodes: [AVAudioNode] = []
    private var limiter: AVAudioUnitEffect?
    private var displayLink: CADisplayLink?
    private let clock = PlayheadClock()
    private var playStartedAt: TimeInterval = 0
    private var playheadAtStart: TimeInterval = 0
    private var episodeDuration: TimeInterval = 0

    init() {
        installOutputChain()
        warmUp()
    }

    func toggle(episode: Episode, mediaRoot: URL) {
        if isPlaying {
            stop()
        } else {
            play(episode: episode, mediaRoot: mediaRoot)
        }
    }

    func play(episode: Episode, mediaRoot: URL) {
        clearPlayers()
        warmUp(mix: episode.mix)

        episodeDuration = max(episode.contentDuration, playhead + 0.1)
        playheadAtStart = playhead
        let anySolo = episode.tracks.contains(where: \.solo)
        var jobs: [ScheduledClip] = []

        for track in episode.tracks {
            if track.muted { continue }
            if anySolo && !track.solo { continue }
            for clip in track.clips {
                guard clip.endTime > playhead else { continue }
                guard let url = mediaRoot.boothFile(clip.playbackFilename),
                      let file = try? AVAudioFile(forReading: url) else { continue }
                if let job = attach(clip: clip, track: track, episode: episode, file: file) {
                    jobs.append(job)
                }
            }
        }

        let (startHost, leadIn) = playbackAnchor()
        for job in jobs {
            let when = AVAudioTime(hostTime: startHost + AVAudioTime.hostTime(forSeconds: job.delay))
            job.player.scheduleSegment(
                job.file,
                startingFrame: job.startingFrame,
                frameCount: job.frameCount,
                at: when
            )
            job.player.play(at: AVAudioTime(hostTime: startHost))
        }

        isPlaying = true
        playStartedAt = CACurrentMediaTime() + leadIn
        startClock()
    }

    func stop() {
        isPlaying = false
        stopClock()
        clearPlayers()
    }

    func shutdown() {
        stop()
        if engine.isRunning {
            engine.stop()
        }
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

    private func installOutputChain() {
        guard limiter == nil else { return }
        let unit = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
        engine.attach(unit)
        engine.connect(engine.mainMixerNode, to: unit, format: nil)
        engine.connect(unit, to: engine.outputNode, format: nil)
        limiter = unit
        configureLimiter(unit, mix: MixSettings())
    }

    private func warmUp(mix: MixSettings = MixSettings()) {
        do {
            try AudioSession.configurePlayback()
        } catch {
            print("session error")
        }
        installOutputChain()
        if let limiter {
            configureLimiter(limiter, mix: mix)
        }
        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                print("engine start error")
            }
        }
    }

    private func playbackAnchor() -> (host: UInt64, lead: TimeInterval) {
        let lead: TimeInterval = engine.isRunning ? 0.02 : 0.05
        if let last = engine.outputNode.lastRenderTime, last.isHostTimeValid {
            let host = last.hostTime + AVAudioTime.hostTime(forSeconds: lead)
            let now = mach_absolute_time()
            return (host > now ? host : now + AVAudioTime.hostTime(forSeconds: lead), lead)
        }
        return (mach_absolute_time() + AVAudioTime.hostTime(forSeconds: lead), lead)
    }

    private func startClock() {
        stopClock()
        clock.onTick = { [weak self] in
            Task { @MainActor in
                self?.tickPlayhead()
            }
        }
        let link = CADisplayLink(target: clock, selector: #selector(PlayheadClock.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 60, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopClock() {
        displayLink?.invalidate()
        displayLink = nil
        clock.onTick = nil
    }

    private func tickPlayhead() {
        guard isPlaying else { return }
        let elapsed = audioElapsed() ?? max(0, CACurrentMediaTime() - playStartedAt)
        let next = min(playheadAtStart + elapsed, episodeDuration)
        playhead = next
        if next >= episodeDuration {
            playhead = episodeDuration
            stop()
        }
    }

    private func audioElapsed() -> TimeInterval? {
        for player in players where player.isPlaying {
            guard let nodeTime = player.lastRenderTime, nodeTime.isSampleTimeValid,
                  let playerTime = player.playerTime(forNodeTime: nodeTime),
                  playerTime.isSampleTimeValid else { continue }
            let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
            if elapsed >= 0 { return elapsed }
        }
        return nil
    }

    private func clearPlayers() {
        players.forEach { $0.stop() }
        players.forEach { engine.detach($0) }
        effectNodes.forEach { engine.detach($0) }
        players.removeAll()
        effectNodes.removeAll()
    }

    private func attach(clip: Clip, track: Track, episode: Episode, file: AVAudioFile) -> ScheduledClip? {
        let sampleRate = file.processingFormat.sampleRate
        let localOffset = max(0, playhead - clip.startOnTimeline)
        let sourceStart = min(file.length, AVAudioFramePosition((clip.sourceOffset + localOffset) * sampleRate))
        let remaining = clip.duration - localOffset
        guard remaining > 0.01 else { return nil }
        let frames = min(AVAudioFrameCount(remaining * sampleRate), AVAudioFrameCount(max(0, file.length - sourceStart)))
        guard frames > 0 else { return nil }

        let player = AVAudioPlayerNode()
        engine.attach(player)
        let format = file.processingFormat
        let useEffects = !episode.mix.bypassEffects && clip.effects.needsGraphEffects
        if useEffects {
            let isolatorEQ = AVAudioUnitEQ(numberOfBands: 6)
            configureIsolator(isolatorEQ, clip: clip, mix: episode.mix)
            let eq = AVAudioUnitEQ(numberOfBands: 8)
            configureEQ(eq, clip: clip, mix: episode.mix)
            let dynamics = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_DynamicsProcessor,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            ))
            configureDynamics(dynamics, clip: clip, mix: episode.mix)
            engine.attach(isolatorEQ)
            engine.attach(eq)
            engine.attach(dynamics)
            engine.connect(player, to: isolatorEQ, format: format)
            engine.connect(isolatorEQ, to: eq, format: format)
            engine.connect(eq, to: dynamics, format: format)
            engine.connect(dynamics, to: engine.mainMixerNode, format: format)
            effectNodes.append(isolatorEQ)
            effectNodes.append(eq)
            effectNodes.append(dynamics)
        } else {
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }

        var volume = clip.linearGain * Float(track.volume)
        if episode.mix.duckingEnabled, track.kind != .voice {
            let overlapsVoice = episode.tracks.contains { track in
                track.kind == .voice && track.clips.contains { $0.endTime > clip.startOnTimeline && $0.startOnTimeline < clip.endTime }
            }
            if overlapsVoice {
                volume *= MixMath.duckGain(voiceAmplitude: 0.6, amount: episode.mix.duckingAmount)
            }
        }
        player.volume = volume
        player.pan = Float(max(-1, min(1, track.pan)))
        players.append(player)
        return ScheduledClip(
            player: player,
            file: file,
            startingFrame: sourceStart,
            frameCount: frames,
            delay: max(0, clip.startOnTimeline - playhead)
        )
    }

    private func configureEQ(_ eq: AVAudioUnitEQ, clip: Clip, mix: MixSettings) {
        let bands = eq.bands
        func setBand(_ index: Int, type: AVAudioUnitEQFilterType, freq: Float, gain: Float, bw: Float = 1.0, bypass: Bool) {
            guard bands.indices.contains(index) else { return }
            bands[index].filterType = type
            bands[index].frequency = freq
            bands[index].bandwidth = bw
            bands[index].gain = gain
            bands[index].bypass = bypass
        }

        let bypass = mix.bypassEffects || clip.effects.bypassEffects
        let eqOn = !bypass && clip.effects.eqEnabled
        setBand(0, type: .parametric, freq: 120, gain: Float(clip.effects.bass), bypass: !eqOn)
        setBand(1, type: .parametric, freq: 1000, gain: Float(clip.effects.mid), bypass: !eqOn)
        setBand(2, type: .parametric, freq: 6000, gain: Float(clip.effects.treble), bypass: !eqOn)

        let noiseOn = !bypass && clip.effects.noiseEnabled
        let noiseHz = Float(70 + clip.effects.noiseAmount * 140)
        setBand(3, type: .highPass, freq: noiseHz, gain: 0, bw: 0.6, bypass: !noiseOn)

        let echoOn = !bypass && clip.effects.echoEnabled
        let amount = Float(clip.effects.echoAmount)
        setBand(4, type: .highPass, freq: 80 + amount * 70, gain: 0, bw: 0.7, bypass: !echoOn)
        setBand(5, type: .parametric, freq: 280, gain: -3.5 * amount, bw: 1.2, bypass: !echoOn)
        setBand(6, type: .parametric, freq: 4500, gain: -2.5 * amount, bw: 1.4, bypass: !echoOn)
        setBand(7, type: .parametric, freq: 700, gain: -2.0 * amount, bw: 0.9, bypass: !echoOn)
    }

    private func configureIsolator(_ eq: AVAudioUnitEQ, clip: Clip, mix: MixSettings) {
        let bands = eq.bands
        func setBand(_ index: Int, type: AVAudioUnitEQFilterType, freq: Float, gain: Float, bw: Float = 1.0, bypass: Bool) {
            guard bands.indices.contains(index) else { return }
            bands[index].filterType = type
            bands[index].frequency = freq
            bands[index].bandwidth = bw
            bands[index].gain = gain
            bands[index].bypass = bypass
        }
        let bypass = mix.bypassEffects || clip.effects.bypassEffects
        if bypass {
            for index in 0..<bands.count { bands[index].bypass = true }
            return
        }
        if let profile = VoiceIsolator.profile(clip.effects.isolatorPreset, amount: clip.effects.isolatorAmount) {
            setBand(0, type: .highPass, freq: profile.highPass, gain: 0, bw: 0.7, bypass: false)
            setBand(1, type: .lowPass, freq: profile.lowPass, gain: 0, bw: 0.7, bypass: false)
            setBand(2, type: .parametric, freq: profile.mudHz, gain: profile.mudGain, bw: 1.1, bypass: false)
            setBand(3, type: .parametric, freq: profile.presenceHz, gain: profile.presenceGain, bw: 0.9, bypass: false)
            setBand(4, type: .parametric, freq: profile.deEssHz, gain: profile.deEssGain, bw: 1.2, bypass: false)
            setBand(5, type: .parametric, freq: 700, gain: profile.mudGain * 0.45, bw: 0.8, bypass: false)
        } else {
            setBand(0, type: .highPass, freq: Float(clip.effects.highPassHz), gain: 0, bw: 0.7, bypass: !clip.effects.highPassEnabled)
            setBand(1, type: .lowPass, freq: 16_000, gain: 0, bw: 0.7, bypass: true)
            setBand(2, type: .parametric, freq: 250, gain: 0, bw: 1, bypass: true)
            setBand(3, type: .parametric, freq: 3_200, gain: 0, bw: 1, bypass: true)
            setBand(4, type: .parametric, freq: 7_500, gain: -6 * Float(clip.effects.deEssAmount), bw: 1.2, bypass: !clip.effects.deEssEnabled)
            setBand(5, type: .parametric, freq: 700, gain: 0, bw: 0.8, bypass: true)
        }
        if clip.effects.highPassEnabled, VoiceIsolator.profile(clip.effects.isolatorPreset, amount: clip.effects.isolatorAmount) != nil {
            bands[0].frequency = max(bands[0].frequency, Float(clip.effects.highPassHz))
            bands[0].bypass = false
        }
        if clip.effects.deEssEnabled, VoiceIsolator.profile(clip.effects.isolatorPreset, amount: clip.effects.isolatorAmount) != nil {
            bands[4].gain = min(bands[4].gain, -6 * Float(clip.effects.deEssAmount))
            bands[4].bypass = false
        }
    }

    private func configureDynamics(_ unit: AVAudioUnitEffect, clip: Clip, mix: MixSettings) {
        let au = unit.audioUnit
        let bypass = mix.bypassEffects || clip.effects.bypassEffects
        let preset = clip.effects.compressorPreset
        let compressorOn = !bypass && clip.effects.compressorEnabled && preset != .off
        AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, compressorOn ? preset.threshold : 0, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, compressorOn ? 0.01 : 0.005, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, compressorOn ? 0.12 : 0.08, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, compressorOn ? Float(clip.effects.makeupGainDB) : 0, 0)

        if !bypass, let isolator = VoiceIsolator.profile(clip.effects.isolatorPreset, amount: clip.effects.isolatorAmount) {
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionThreshold, kAudioUnitScope_Global, 0, isolator.expansionThreshold, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, isolator.expansionRatio, 0)
            if !compressorOn {
                AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, isolator.makeup, 0)
            }
        } else if !bypass, clip.effects.echoEnabled {
            let amount = Float(clip.effects.echoAmount)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionThreshold, kAudioUnitScope_Global, 0, -42 + amount * 14, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 1.8 + amount * 6, 0)
        } else {
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 1, 0)
        }
    }

    private func configureLimiter(_ unit: AVAudioUnitEffect, mix: MixSettings) {
        let au = unit.audioUnit
        let preGain: Float = mix.limiterEnabled && !mix.bypassEffects ? Float(max(0, -mix.limiterCeilingDB)) : 0
        AudioUnitSetParameter(au, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.001, 0)
        AudioUnitSetParameter(au, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.05, 0)
        AudioUnitSetParameter(au, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, preGain, 0)
    }
}

private struct ScheduledClip {
    let player: AVAudioPlayerNode
    let file: AVAudioFile
    let startingFrame: AVAudioFramePosition
    let frameCount: AVAudioFrameCount
    let delay: TimeInterval
}

private final class PlayheadClock: NSObject {
    var onTick: (() -> Void)?

    @objc func fire() {
        onTick?()
    }
}
