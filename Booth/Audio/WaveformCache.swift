import AVFoundation
import Foundation

final class WaveformCache {
    static let shared = WaveformCache()
    private var cache: [String: [Float]] = [:]
    private let lock = NSLock()

    func peaks(url: URL, count: Int = 160) -> [Float] {
        let key = "\(url.path)#\(count)"
        lock.lock()
        if let existing = cache[key] {
            lock.unlock()
            return existing
        }
        lock.unlock()
        let computed = Self.compute(url: url, count: count)
        lock.lock()
        cache[key] = computed
        lock.unlock()
        return computed
    }

    private static func compute(url: URL, count: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let total = Int(file.length)
        guard total > 0 else { return [] }
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        var result = [Float](repeating: 0, count: count)
        let chunk = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk)) else { return [] }
        var frame: AVAudioFramePosition = 0
        while frame < file.length {
            file.framePosition = frame
            let remaining = Int(file.length - frame)
            let toRead = AVAudioFrameCount(min(chunk, remaining))
            do {
                try file.read(into: buffer, frameCount: toRead)
            } catch {
                break
            }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let data = buffer.floatChannelData else { break }
            for i in 0..<frames {
                var sample: Float = 0
                for ch in 0..<channels {
                    sample = max(sample, abs(data[ch][i]))
                }
                let global = Int(frame) + i
                let bin = min(count - 1, global * count / total)
                result[bin] = max(result[bin], sample)
            }
            frame += AVAudioFramePosition(frames)
        }
        return result
    }
}
