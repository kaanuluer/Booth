import SwiftUI

enum BoothTheme {
    static let canvas = Color(red: 0.043, green: 0.047, blue: 0.055)
    static let surface = Color(red: 0.086, green: 0.094, blue: 0.110)
    static let elevated = Color(red: 0.118, green: 0.129, blue: 0.149)
    static let hairline = Color(red: 0.165, green: 0.176, blue: 0.200)
    static let text = Color(red: 0.957, green: 0.945, blue: 0.918)
    static let secondary = Color(red: 0.604, green: 0.584, blue: 0.549)
    static let accent = Color(red: 1.0, green: 0.302, blue: 0.227)
    static let voice = Color(red: 0.369, green: 0.784, blue: 0.773)
    static let music = Color(red: 0.910, green: 0.647, blue: 0.294)
    static let sfx = Color(red: 0.545, green: 0.486, blue: 1.0)
    static let aux = Color(red: 0.55, green: 0.58, blue: 0.62)
    static let success = Color(red: 0.239, green: 0.863, blue: 0.592)

    static func trackColor(_ kind: TrackKind) -> Color {
        switch kind {
        case .voice: return voice
        case .music: return music
        case .sfx: return sfx
        case .aux: return aux
        }
    }
}

enum TimeCode {
    static func format(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let hours = Int(t) / 3600
        let minutes = (Int(t) % 3600) / 60
        let seconds = Int(t) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static func short(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func decibels(_ value: Double) -> String {
        String(format: "%+.1f dB", value)
    }
}
