import Foundation

enum VoiceIsolator {
    struct Profile {
        var highPass: Float
        var lowPass: Float
        var mudHz: Float
        var mudGain: Float
        var presenceHz: Float
        var presenceGain: Float
        var deEssHz: Float
        var deEssGain: Float
        var gate: Float
        var echo: Float
        var expansionThreshold: Float
        var expansionRatio: Float
        var makeup: Float
    }

    struct State {
        var previous = Float(0)
        var highPass = Float(0)
        var lowPass = Float(0)
    }

    static func profile(_ preset: VoiceIsolatorPreset, amount: Double) -> Profile? {
        guard preset.isOn else { return nil }
        let a = Float(max(0, min(1, amount)))
        switch preset {
        case .off:
            return nil
        case .cleanVocals:
            return Profile(
                highPass: 85 + a * 25,
                lowPass: 12_500 - a * 1_500,
                mudHz: 240,
                mudGain: -2.2 * a,
                presenceHz: 3_200,
                presenceGain: 3.4 * a,
                deEssHz: 7_400,
                deEssGain: -2.2 * a,
                gate: 0.012 + a * 0.018,
                echo: 0.22 * a,
                expansionThreshold: -36 + a * 8,
                expansionRatio: 1.6 + a * 2.2,
                makeup: 1.2 * a
            )
        case .lecture:
            return Profile(
                highPass: 120 + a * 40,
                lowPass: 8_400 - a * 1_200,
                mudHz: 280,
                mudGain: -5.5 * a,
                presenceHz: 2_150,
                presenceGain: 4.2 * a,
                deEssHz: 8_000,
                deEssGain: -1.4 * a,
                gate: 0.02 + a * 0.035,
                echo: 0.48 * a,
                expansionThreshold: -40 + a * 10,
                expansionRatio: 3.2 + a * 5.5,
                makeup: 2.0 * a
            )
        }
    }

    static func process(_ input: Float, state: inout State, profile: Profile, delayed1: Float, delayed2: Float) -> Float {
        let hpCoeff: Float = 0.93
        state.highPass = hpCoeff * (state.highPass + input - state.previous)
        state.previous = input

        let lpCoeff = max(0.05, min(0.35, profile.lowPass / 18_000))
        state.lowPass += lpCoeff * (state.highPass - state.lowPass)
        var sample = state.lowPass

        sample += sample * (profile.presenceGain * 0.018)
        sample += sample * (profile.mudGain * 0.012)
        if abs(sample) > 0.18 {
            sample += sample * (profile.deEssGain * 0.01)
        }

        sample -= delayed1 * (0.40 * profile.echo)
        sample -= delayed2 * (0.20 * profile.echo)

        if abs(sample) < profile.gate {
            sample *= max(0.12, 1 - profile.echo - 0.45)
        }

        sample *= 1 + profile.makeup * 0.04
        return max(-1, min(1, sample))
    }
}
