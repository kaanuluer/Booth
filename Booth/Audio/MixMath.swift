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

    static func panGains(_ pan: Double) -> (left: Float, right: Float) {
        let clamped = max(-1, min(1, pan))
        let angle = (clamped + 1) * Double.pi / 4
        return (Float(cos(angle)), Float(sin(angle)))
    }

    static func punchReplace(clips: [Clip], punch: Clip) -> [Clip] {
        let punchStart = punch.startOnTimeline
        let punchEnd = punch.endTime
        var next: [Clip] = []
        for clip in clips {
            if clip.endTime <= punchStart + 0.01 || clip.startOnTimeline >= punchEnd - 0.01 {
                next.append(clip)
                continue
            }
            if clip.startOnTimeline < punchStart - 0.01 {
                var left = clip
                left.id = UUID()
                left.duration = punchStart - clip.startOnTimeline
                if left.duration >= 0.05 { next.append(left) }
            }
            if clip.endTime > punchEnd + 0.01 {
                var right = clip
                right.id = UUID()
                let delta = punchEnd - clip.startOnTimeline
                right.startOnTimeline = punchEnd
                right.sourceOffset = clip.sourceOffset + delta
                right.duration = clip.endTime - punchEnd
                if right.duration >= 0.05 { next.append(right) }
            }
        }
        next.append(punch)
        return next.sorted { $0.startOnTimeline < $1.startOnTimeline }
    }

    static func invertCuts(duration: TimeInterval, cuts: [Region], pad: TimeInterval = 0.05) -> [Region] {
        let sorted = cuts.sorted { $0.start < $1.start }
        var keep: [Region] = []
        var cursor: TimeInterval = 0
        for cut in sorted {
            let start = max(0, cut.start - pad)
            let end = min(duration, cut.end + pad)
            if start > cursor + 0.05 {
                keep.append(Region(start: cursor, duration: start - cursor))
            }
            cursor = max(cursor, end)
        }
        if duration - cursor >= 0.05 {
            keep.append(Region(start: cursor, duration: duration - cursor))
        }
        return keep
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

    static func gaps(in clips: [Clip], minDuration: TimeInterval = 0.08) -> [(start: TimeInterval, duration: TimeInterval)] {
        let sorted = clips.sorted { $0.startOnTimeline < $1.startOnTimeline }
        guard sorted.count >= 2 else { return [] }
        var result: [(start: TimeInterval, duration: TimeInterval)] = []
        for index in 0..<(sorted.count - 1) {
            let gapStart = sorted[index].endTime
            let duration = sorted[index + 1].startOnTimeline - gapStart
            if duration >= minDuration {
                result.append((gapStart, duration))
            }
        }
        return result
    }

    static func packClips(_ clips: [Clip]) -> [Clip] {
        let sorted = clips.sorted { $0.startOnTimeline < $1.startOnTimeline }
        var cursor: TimeInterval?
        return sorted.map { clip in
            var next = clip
            if let cursor, next.startOnTimeline > cursor + 0.001 {
                next.startOnTimeline = cursor
            }
            let end = next.endTime
            cursor = cursor.map { max($0, end) } ?? end
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
