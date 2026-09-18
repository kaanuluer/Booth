import Foundation

enum MixMath {
    struct Region: Equatable {
        var start: TimeInterval
        var duration: TimeInterval
        var end: TimeInterval { start + duration }
    }

    struct Trim: Equatable {
        var startOnTimeline: TimeInterval
        var sourceOffset: TimeInterval
        var duration: TimeInterval
    }

    static func duckGain(voiceAmplitude: Float, amount: Double, threshold: Float = 0.03, floor: Float = 0.14) -> Float {
        let strength = Float(max(0, min(1, amount)))
        guard strength > 0.001, voiceAmplitude > threshold else { return 1 }
        let span = max(0.0001, 1 - threshold)
        let t = min(1, (voiceAmplitude - threshold) / span)
        return 1 - t * strength * (1 - floor)
    }

    static func autoLevelGain(rms: Float, targetDB: Float = -18) -> Float {
        let rmsDB = 20 * log10(max(rms, 0.00001))
        let delta = targetDB - rmsDB
        return pow(10, max(-12, min(12, delta)) / 20)
    }

    static func limit(_ sample: Float, ceiling: Float, envelope: inout Float, attack: Float = 0.02, release: Float = 0.002) -> Float {
        let magnitude = abs(sample)
        if magnitude > envelope {
            envelope += (magnitude - envelope) * attack
        } else {
            envelope += (magnitude - envelope) * release
        }
        let cap = max(0.05, ceiling)
        var limited = sample
        if envelope > cap {
            limited = sample * (cap / envelope)
        }
        return max(-cap, min(cap, limited))
    }

    static func voicedRegions(
        levels: [Float],
        sampleRate: Double,
        hop: Int,
        threshold: Float,
        minSilence: TimeInterval,
        minKeep: TimeInterval
    ) -> [Region] {
        guard !levels.isEmpty, sampleRate > 0, hop > 0 else { return [] }
        let frameDur = Double(hop) / sampleRate
        var regions: [Region] = []
        var start: Int?
        for (index, level) in levels.enumerated() {
            let voiced = level >= threshold
            if voiced, start == nil {
                start = index
            }
            if !voiced, let origin = start {
                appendRegion(from: origin, to: index, frameDur: frameDur, minKeep: minKeep, into: &regions)
                start = nil
            }
        }
        if let origin = start {
            appendRegion(from: origin, to: levels.count, frameDur: frameDur, minKeep: minKeep, into: &regions)
        }
        return merge(regions, maxGap: minSilence)
    }

    static func trimStart(
        startOnTimeline: TimeInterval,
        sourceOffset: TimeInterval,
        duration: TimeInterval,
        sourceDuration: TimeInterval,
        delta: TimeInterval
    ) -> Trim {
        let maxLeft = sourceOffset
        let maxRight = max(0, duration - 0.05)
        let shift = min(maxRight, max(-maxLeft, delta))
        return Trim(
            startOnTimeline: max(0, startOnTimeline + shift),
            sourceOffset: sourceOffset + shift,
            duration: duration - shift
        )
    }

    static func trimEnd(duration: TimeInterval, sourceOffset: TimeInterval, sourceDuration: TimeInterval, delta: TimeInterval) -> TimeInterval {
        let maxDuration = max(0.05, sourceDuration - sourceOffset)
        return min(maxDuration, max(0.05, duration + delta))
    }

    static func rippleShift(clips: [Clip], removedStart: TimeInterval, removedDuration: TimeInterval) -> [Clip] {
        clips.map { clip in
            var next = clip
            if clip.startOnTimeline >= removedStart + removedDuration - 0.0001 {
                next.startOnTimeline = max(0, clip.startOnTimeline - removedDuration)
            }
            return next
        }
    }

    private static func appendRegion(from origin: Int, to end: Int, frameDur: TimeInterval, minKeep: TimeInterval, into regions: inout [Region]) {
        let duration = Double(end - origin) * frameDur
        guard duration >= minKeep else { return }
        regions.append(Region(start: Double(origin) * frameDur, duration: duration))
    }

    private static func merge(_ regions: [Region], maxGap: TimeInterval) -> [Region] {
        guard var current = regions.first else { return [] }
        var merged: [Region] = []
        for region in regions.dropFirst() {
            if region.start - current.end <= maxGap {
                current.duration = region.end - current.start
            } else {
                merged.append(current)
                current = region
            }
        }
        merged.append(current)
        return merged
    }
}
