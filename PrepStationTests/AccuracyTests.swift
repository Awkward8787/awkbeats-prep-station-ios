import XCTest
@testable import PrepStation

/// Runs detection on the 20 encoded test beats in Fixtures (MP3, WAV, FLAC, M4A, AIFF) with known key and BPM,
/// prints a table, and guards against regressions.
final class AccuracyTests: XCTestCase {
    struct Truth: Decodable { let file: String; let key: String; let bpm: Double; let set: String }

    func testAccuracyOnFixtureBeats() throws {
        let bundle = Bundle(for: Self.self)
        let truthURL = try XCTUnwrap(bundle.url(forResource: "truth", withExtension: "json", subdirectory: "Fixtures"))
        let truth = try JSONDecoder().decode([Truth].self, from: Data(contentsOf: truthURL))
        var keyExact = 0, keyRelative = 0, bpmExact = 0, bpmOctave = 0
        var lines: [String] = []
        for t in truth {
            let url = try XCTUnwrap(bundle.url(forResource: t.file, withExtension: nil, subdirectory: "Fixtures"))
            let start = Date()
            let r = try TrackAnalyzer.analyze(url: url)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let want = Camelot.parse(t.key)!
            let gotKey = r.key
            let exactK = gotKey == want
            let relK = !exactK && gotKey.map { Int($0.camelot.dropLast()) == Int(want.camelot.dropLast()) } == true
            let bpm = r.bpm ?? -1
            let exactB = abs(bpm - t.bpm) <= 0.05
            let octB = !exactB && (abs(bpm * 2 - t.bpm) <= 0.1 || abs(bpm / 2 - t.bpm) <= 0.05)
            keyExact += exactK ? 1 : 0; keyRelative += relK ? 1 : 0
            bpmExact += exactB ? 1 : 0; bpmOctave += octB ? 1 : 0
            lines.append("ACC \(t.set) \(t.file) key \(t.key) -> \(gotKey?.name ?? "nil") \(exactK ? "OK" : relK ? "RELATIVE" : "MISS") conf \(String(format: "%.2f", r.keyConfidence ?? 0)) | bpm \(BpmMath.format(t.bpm)) -> \(BpmMath.format(bpm)) \(exactB ? "OK" : octB ? "OCTAVE" : "MISS") | \(ms) ms")
        }
        lines.forEach { print($0) }
        print("ACC SUMMARY key exact \(keyExact)/\(truth.count), relative \(keyRelative); bpm exact \(bpmExact)/\(truth.count), octave \(bpmOctave)")
        XCTAssertGreaterThanOrEqual(bpmExact, 15)
        XCTAssertGreaterThanOrEqual(keyExact + keyRelative, 18)
    }
}
