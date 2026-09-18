import AVFoundation
import Foundation

final class WaveformCache {
    static let shared = WaveformCache()
    private var cache: [String: [Float]] = [:]
    private var order: [String] = []
    private let lock = NSLock()
    private let limit = 96

    func cached(url: URL, count: Int) -> [Float]? {
        let key = "\(url.path)#\(count)"
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    func peaks(url: URL, count: Int = 64) -> [Float] {
        let key = "\(url.path)#\(count)"
        lock.lock()
        if let existing = cache[key] {
            if let index = order.firstIndex(of: key) {
                order.remove(at: index)
                order.append(key)
            }
            lock.unlock()
            return existing
        }
        lock.unlock()
        let computed = Self.compute(url: url, count: count)
        lock.lock()
        cache[key] = computed
        order.append(key)
        while order.count > limit {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        lock.unlock()
        return computed
    }

    private static func compute(url: URL, count: Int) -> [Float] {
        guard url.isFileURL else { return [] }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return [] }
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let total = Int(file.length)
        guard total > 0, count > 0 else { return [] }
        let format = file.processingFormat
        let channels = max(1, Int(format.channelCount))
        let hop = max(1, total / count)
        let window = min(256, hop)
        var result = [Float](repeating: 0, count: count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(window)) else { return [] }
        for bin in 0..<count {
            let frame = min(max(0, total - 1), bin * hop)
            file.framePosition = AVAudioFramePosition(frame)
            let toRead = AVAudioFrameCount(min(window, total - frame))
            guard toRead > 0 else { break }
            do {
                try file.read(into: buffer, frameCount: toRead)
            } catch {
                break
            }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let data = buffer.floatChannelData else { continue }
            var peak: Float = 0
            for i in 0..<frames {
                var sample: Float = 0
                for channel in 0..<channels {
                    sample = max(sample, abs(data[channel][i]))
                }
                if sample > peak { peak = sample }
            }
            result[bin] = peak
        }
        return result
    }
}
