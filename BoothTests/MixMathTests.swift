import XCTest
@testable import Booth

final class MixMathTests: XCTestCase {
    func testDuckGainSilentStaysUnity() {
        XCTAssertEqual(MixMath.duckGain(voiceAmplitude: 0.01, amount: 0.8), 1, accuracy: 0.001)
    }

    func testDuckGainLoudReducesMusic() {
        let gain = MixMath.duckGain(voiceAmplitude: 0.8, amount: 0.8)
        XCTAssertLessThan(gain, 0.5)
        XCTAssertGreaterThan(gain, 0.1)
    }

    func testAutoLevelBoostsQuiet() {
        let gain = MixMath.autoLevelGain(rms: 0.02, targetDB: -18)
        XCTAssertGreaterThan(gain, 1)
    }

    func testLimiterCapsPeak() {
        var env: Float = 0
        var peak: Float = 0
        for _ in 0..<200 {
            let out = MixMath.limit(0.99, ceiling: 0.89, envelope: &env)
            peak = max(peak, abs(out))
        }
        XCTAssertLessThanOrEqual(peak, 0.89 + 0.0001)
    }

    func testVoicedRegionsDropsSilence() {
        var levels = [Float](repeating: 0.001, count: 40)
        for i in 10..<25 { levels[i] = 0.2 }
        let regions = MixMath.voicedRegions(
            levels: levels,
            sampleRate: 100,
            hop: 10,
            threshold: 0.05,
            minSilence: 0.2,
            minKeep: 0.2
        )
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].start, 1, accuracy: 0.05)
        XCTAssertGreaterThan(regions[0].duration, 1)
    }

    func testTrimStartMovesOffset() {
        let trim = MixMath.trimStart(
            startOnTimeline: 2,
            sourceOffset: 1,
            duration: 5,
            sourceDuration: 10,
            delta: 0.5
        )
        XCTAssertEqual(trim.startOnTimeline, 2.5, accuracy: 0.0001)
        XCTAssertEqual(trim.sourceOffset, 1.5, accuracy: 0.0001)
        XCTAssertEqual(trim.duration, 4.5, accuracy: 0.0001)
    }

    func testTrimEndClampsToSource() {
        let duration = MixMath.trimEnd(duration: 4, sourceOffset: 1, sourceDuration: 6, delta: 10)
        XCTAssertEqual(duration, 5, accuracy: 0.0001)
    }

    func testEnhancerRemovesDC() {
        let input = [Float](repeating: 0.4, count: 2048)
        let output = SpectralEnhancer.process(input, sampleRate: 48_000, amount: 0.8, lecture: false)
        let mean = output.reduce(0, +) / Float(output.count)
        XCTAssertLessThan(abs(mean), 0.05)
    }
}

final class EpisodeEditTests: XCTestCase {
    func testNormalizedTitle() {
        XCTAssertEqual(Episode.normalizedTitle("  "), "Adsız bölüm")
        XCTAssertEqual(Episode.normalizedTitle(" S01E01 — Misafir "), "S01E01 — Misafir")
    }

    func testSplitAndMove() {
        var episode = Episode(title: "Test")
        let clip = Clip(name: "Konuşma", filename: "a.m4a", duration: 10, sourceDuration: 10)
        episode.addClip(clip, to: episode.tracks[0].id)
        episode.splitClip(clip.id, at: 4)
        XCTAssertEqual(episode.clipCount, 2)
        let right = episode.tracks[0].clips[1]
        episode.moveClip(right.id, to: episode.tracks[1].id)
        XCTAssertEqual(episode.tracks[0].clips.count, 1)
        XCTAssertEqual(episode.tracks[1].clips.count, 1)
    }

    func testRippleDelete() {
        var episode = Episode(title: "Test")
        let first = Clip(name: "A", filename: "a.m4a", startOnTimeline: 0, duration: 2, sourceDuration: 2)
        let second = Clip(name: "B", filename: "b.m4a", startOnTimeline: 2, duration: 2, sourceDuration: 2)
        episode.addClip(first, to: episode.tracks[0].id)
        episode.addClip(second, to: episode.tracks[0].id)
        episode.removeClip(first.id, ripple: true)
        XCTAssertEqual(episode.tracks[0].clips.first?.startOnTimeline ?? 99, 0, accuracy: 0.01)
    }

    func testReplaceClipKeepsRegions() {
        var episode = Episode(title: "Test")
        let clip = Clip(name: "Konuşma", filename: "a.m4a", duration: 10, sourceDuration: 10)
        episode.addClip(clip, to: episode.tracks[0].id)
        episode.replaceClip(clip.id, with: [
            MixMath.Region(start: 1, duration: 2),
            MixMath.Region(start: 5, duration: 3)
        ])
        XCTAssertEqual(episode.clipCount, 2)
        XCTAssertEqual(episode.tracks[0].clips[0].duration, 2, accuracy: 0.001)
        XCTAssertEqual(episode.tracks[0].clips[1].startOnTimeline, 5, accuracy: 0.001)
    }

    func testOldEpisodeJSONStillDecodes() throws {
        let original = Episode(title: "Eski")
        let data = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "mix")
        object.removeValue(forKey: "artworkFilename")
        object.removeValue(forKey: "introAssetID")
        object.removeValue(forKey: "outroAssetID")
        object.removeValue(forKey: "transcript")
        object.removeValue(forKey: "showNotes")
        let slim = try JSONSerialization.data(withJSONObject: object)
        let episode = try JSONDecoder().decode(Episode.self, from: slim)
        XCTAssertEqual(episode.title, "Eski")
        XCTAssertTrue(episode.mix.limiterEnabled)
        XCTAssertNil(episode.artworkFilename)
        XCTAssertEqual(episode.transcript, "")
        XCTAssertEqual(episode.tracks[0].pan, 0, accuracy: 0.0001)
    }

    func testApplyShowTemplateDoesNotDuplicate() {
        var episode = Episode(title: "Test")
        let intro = MediaAsset(filename: "intro.m4a", displayName: "Intro", duration: 3, kindHint: .music)
        let outro = MediaAsset(filename: "outro.m4a", displayName: "Outro", duration: 2, kindHint: .music)
        episode.library = [intro, outro]
        episode.introAssetID = intro.id
        episode.outroAssetID = outro.id
        episode.applyShowTemplate()
        episode.applyShowTemplate()
        let music = episode.tracks.first { $0.kind == .music }?.clips ?? []
        XCTAssertEqual(music.filter { $0.filename == "intro.m4a" }.count, 1)
        XCTAssertEqual(music.filter { $0.filename == "outro.m4a" }.count, 1)
        XCTAssertEqual(music.first { $0.filename == "intro.m4a" }?.startOnTimeline ?? 99, 0, accuracy: 0.001)
        XCTAssertGreaterThan(music.first { $0.filename == "outro.m4a" }?.startOnTimeline ?? 0, 2.9)
    }

    @MainActor
    func testUndoRedoRoundTrip() {
        let store = EpisodeStore()
        var episode = store.createEpisode(title: "Once")
        store.checkpoint(episode)
        episode.title = "İki"
        store.save(episode, persistImmediately: true)
        let undone = store.undo(for: episode.id)
        XCTAssertEqual(undone?.title, "Once")
        let redone = store.redo(for: episode.id)
        XCTAssertEqual(redone?.title, "İki")
        store.delete(episode)
    }

    func testPunchReplaceSplitsExistingClip() {
        let existing = Clip(name: "A", filename: "a.m4a", startOnTimeline: 0, duration: 10, sourceDuration: 10)
        let punch = Clip(name: "P", filename: "p.m4a", startOnTimeline: 3, duration: 2, sourceDuration: 2)
        let next = MixMath.punchReplace(clips: [existing], punch: punch)
        XCTAssertEqual(next.count, 3)
        XCTAssertEqual(next[0].duration, 3, accuracy: 0.01)
        XCTAssertEqual(next[1].filename, "p.m4a")
        XCTAssertEqual(next[2].startOnTimeline, 5, accuracy: 0.01)
        XCTAssertEqual(next[2].sourceOffset, 5, accuracy: 0.01)
    }

    func testFillerLexiconDetectsTurkishFillers() {
        XCTAssertTrue(FillerLexicon.isFiller("yani"))
        XCTAssertTrue(FillerLexicon.isFiller("Şey,"))
        XCTAssertFalse(FillerLexicon.isFiller("merhaba"))
    }

    func testInvertCutsKeepsSpeechAroundFillers() {
        let keep = MixMath.invertCuts(
            duration: 4,
            cuts: [MixMath.Region(start: 1.5, duration: 0.3)],
            pad: 0
        )
        XCTAssertEqual(keep.count, 2)
        XCTAssertEqual(keep[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(keep[0].duration, 1.5, accuracy: 0.001)
        XCTAssertEqual(keep[1].start, 1.8, accuracy: 0.001)
    }

    func testShowNotesIncludesChapters() {
        let notes = SpeechTranscriber.showNotes(
            title: "S01E01",
            transcript: "Bugün konuğumuz stüdyoda. Podcast kaydını bitiriyoruz.",
            chapters: [Marker(time: 12, label: "Giriş", isChapter: true)]
        )
        XCTAssertTrue(notes.contains("S01E01"))
        XCTAssertTrue(notes.contains("Giriş"))
        XCTAssertTrue(notes.contains("Özet"))
    }

    func testPanCenterIsUnity() {
        let pan = MixMath.panGains(0)
        XCTAssertEqual(pan.left, pan.right, accuracy: 0.001)
        XCTAssertGreaterThan(pan.left, 0.6)
    }
}
