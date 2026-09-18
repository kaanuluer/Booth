import AVFoundation
import Foundation

enum SpectralEnhancer {
    static func enhanceFile(at url: URL, to destination: URL, amount: Double, lecture: Bool) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 64, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw ExporterError.writeFailed
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw ExporterError.writeFailed }
        var samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        if format.channelCount > 1, let right = buffer.floatChannelData?[1] {
            for i in samples.indices {
                samples[i] = (samples[i] + right[i]) * 0.5
            }
        }
        samples = process(samples, sampleRate: format.sampleRate, amount: amount, lecture: lecture)
        let outFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        let outFile = try AVAudioFile(forWriting: destination, settings: outFormat.settings)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw ExporterError.writeFailed
        }
        outBuffer.frameLength = AVAudioFrameCount(samples.count)
        let count = samples.count
        samples.withUnsafeMutableBufferPointer { src in
            if let dest = outBuffer.floatChannelData?[0], let base = src.baseAddress {
                dest.update(from: base, count: count)
            }
        }
        try outFile.write(from: outBuffer)
    }

    static func process(_ input: [Float], sampleRate: Double, amount: Double, lecture: Bool) -> [Float] {
        guard !input.isEmpty, sampleRate > 0 else { return input }
        let a = Float(max(0, min(1, amount)))
        let hpHz = lecture ? 140.0 : 85.0
        let rc = 1 / (2 * Double.pi * hpHz)
        let alpha = Float(rc / (rc + 1 / sampleRate))
        var previous = Float(0)
        var highPass = Float(0)
        var envelope = Float(0)
        var sibilance = Float(0)

        let window = max(32, Int(0.03 * sampleRate))
        var energies: [Float] = []
        var cursor = 0
        while cursor + window <= input.count {
            var sum: Float = 0
            for i in cursor..<(cursor + window) {
                sum += input[i] * input[i]
            }
            energies.append(sqrt(sum / Float(window)))
            cursor += window
        }
        let noise = energies.sorted().dropLast(max(0, energies.count * 4 / 5)).last ?? 0.01
        let threshold = noise * (1.35 + a * 2.4)

        var output = [Float](repeating: 0, count: input.count)
        for i in input.indices {
            let sample = input[i]
            highPass = alpha * (highPass + sample - previous)
            previous = sample
            var value = highPass
            let magnitude = abs(value)
            envelope += (magnitude - envelope) * (magnitude > envelope ? 0.12 : 0.018)
            if envelope < threshold {
                value *= max(0.04, 1 - a * 0.9)
            }
            sibilance += (abs(value) - sibilance) * 0.08
            if sibilance > 0.11 {
                value *= 1 - a * (lecture ? 0.22 : 0.38)
            }
            if lecture {
                value *= 1 + a * 0.08
            }
            output[i] = max(-0.98, min(0.98, value))
        }
        return output
    }

    static func frameLevels(samples: [Float], hop: Int) -> [Float] {
        guard hop > 0, !samples.isEmpty else { return [] }
        var levels: [Float] = []
        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + hop)
            var sum: Float = 0
            for i in index..<end {
                sum += samples[i] * samples[i]
            }
            levels.append(sqrt(sum / Float(max(1, end - index))))
            index += hop
        }
        return levels
    }

    static func loadMono(url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let frames = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
            return ([], file.processingFormat.sampleRate)
        }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData?[0] else { return ([], file.processingFormat.sampleRate) }
        var samples = Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
        if file.processingFormat.channelCount > 1, let right = buffer.floatChannelData?[1] {
            for i in samples.indices {
                samples[i] = (samples[i] + right[i]) * 0.5
            }
        }
        return (samples, file.processingFormat.sampleRate)
    }
}
