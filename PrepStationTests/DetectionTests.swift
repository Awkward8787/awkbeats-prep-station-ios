import XCTest
@testable import PrepStation

/// Synthetic audio with a known answer (same generators the desktop tests use).
final class DetectionTests: XCTestCase {
    func testKeyOnScaleTonesAll24Keys() {
        for key in Camelot.allKeys {
            let tone = SyntheticAudio.keyedTone(key, seconds: 3, sampleRate: 22050)
            let est = KeyDetector.detect(tone, sampleRate: 22050)
            XCTAssertEqual(est.key, key, "expected \(key.name), got \(est.key.name)")
        }
    }

    func testKeySilenceHasNoConfidence() {
        let est = KeyDetector.detect([Float](repeating: 0, count: 44100), sampleRate: 44100)
        XCTAssertEqual(est.confidence, 0)
    }

    func testBpmOnSyntheticBeats() throws {
        let cases: [(String, Double)] = [("A minor", 140), ("C major", 90), ("F# minor", 72.5), ("D# major", 128), ("G minor", 102.75)]
        for (name, bpm) in cases {
            let key = Camelot.parse(name)!
            let x = SyntheticAudio.beat(key: key, bpm: bpm, bars: 8, sampleRate: 22050)
            let est = try BpmDetector.detect(x, sampleRate: 22050)
            // Exact to 0.05 BPM, or the half/double-time reading (the app offers ½× and 2×).
            let ok = abs(est.bpm - bpm) <= 0.05 || abs(est.bpm * 2 - bpm) <= 0.1 || abs(est.bpm / 2 - bpm) <= 0.05
            XCTAssertTrue(ok, "\(bpm) BPM detected as \(est.bpm)")
        }
    }

    func testBpmClicksExact() throws {
        for bpm in [85.0, 120.0, 93.33] {
            let x = SyntheticAudio.clicks(bpm: bpm, seconds: 20, sampleRate: 44100)
            let est = try BpmDetector.detect(x, sampleRate: 44100)
            let ok = abs(est.bpm - bpm) <= 0.02 || abs(est.bpm / 2 - bpm) <= 0.02 || abs(est.bpm * 2 - bpm) <= 0.04
            XCTAssertTrue(ok, "\(bpm) clicks detected as \(est.bpm)")
        }
    }

    func testBpmTooShortThrows() {
        XCTAssertThrowsError(try BpmDetector.detect([Float](repeating: 0, count: 1000), sampleRate: 44100))
    }

    func testPercentileMatchesNumpy() {
        XCTAssertEqual(BpmDetector.percentile([1, 2, 3, 4, 5], 0.9), 4.6, accuracy: 1e-9)
    }
}
