import XCTest
@testable import PrepStation

final class CamelotAndMathTests: XCTestCase {
    func testCamelotCodes() {
        XCTAssertEqual(Camelot.key(9, .minor).camelot, "8A")   // A minor
        XCTAssertEqual(Camelot.key(0, .major).camelot, "8B")   // C major
        XCTAssertEqual(Camelot.key(6, .minor).camelot, "11A")  // F# minor
        XCTAssertEqual(Camelot.key(11, .major).camelot, "1B")  // B major
    }

    func testParseVariants() {
        XCTAssertEqual(Camelot.parse("8A"), Camelot.key(9, .minor))
        XCTAssertEqual(Camelot.parse("12b"), Camelot.key(4, .major))
        XCTAssertEqual(Camelot.parse("A minor"), Camelot.key(9, .minor))
        XCTAssertEqual(Camelot.parse("Am"), Camelot.key(9, .minor))
        XCTAssertEqual(Camelot.parse("Bbm"), Camelot.key(10, .minor))
        XCTAssertEqual(Camelot.parse("F# maj"), Camelot.key(6, .major))
        XCTAssertEqual(Camelot.parse("E♭"), Camelot.key(3, .major))
        XCTAssertEqual(Camelot.parse("C"), Camelot.key(0, .major))
        XCTAssertNil(Camelot.parse("13A"))
        XCTAssertNil(Camelot.parse("H minor"))
        XCTAssertNil(Camelot.parse(""))
    }

    func testAllKeysRoundTrip() {
        XCTAssertEqual(Camelot.allKeys.count, 24)
        for key in Camelot.allKeys {
            XCTAssertEqual(Camelot.parse(key.camelot), key)
            XCTAssertEqual(Camelot.parse(key.name), key)
            XCTAssertEqual(Camelot.parse(key.shortName), key)
        }
    }

    func testTriad() {
        XCTAssertEqual(Camelot.key(9, .minor).triad, [9, 0, 4])   // A C E
        XCTAssertEqual(Camelot.key(0, .major).triad, [0, 4, 7])   // C E G
    }

    func testBpmMath() {
        XCTAssertEqual(BpmMath.tidy(139.98), 140)
        XCTAssertEqual(BpmMath.tidy(102.75), 102.75)
        XCTAssertEqual(BpmMath.format(140), "140")
        XCTAssertEqual(BpmMath.format(93.5), "93.5")
        XCTAssertEqual(BpmMath.format(102.75), "102.75")
        XCTAssertEqual(BpmMath.working(detected: 140, scale: 0.5, override: nil), 70)
        XCTAssertEqual(BpmMath.working(detected: 70, scale: 2, override: nil), 140)
        XCTAssertEqual(BpmMath.working(detected: 70, scale: 2, override: 141.5), 141.5)
        XCTAssertNil(BpmMath.working(detected: nil, scale: 1, override: nil))
        XCTAssertFalse(BpmMath.inRange(39)); XCTAssertTrue(BpmMath.inRange(300))
    }

    func testReferenceNotes() {
        let am = Camelot.key(9, .minor)
        let chord = KeyReference.notes(.chord, key: am)
        XCTAssertEqual(Set(chord.map { $0.midi % 12 }), [9, 0, 4])
        XCTAssertEqual(chord.first?.midi, 45)  // A2 bass under A3
        let drone = KeyReference.notes(.drone, key: am)
        XCTAssertTrue(drone.allSatisfy { $0.duration.isInfinite })
        XCTAssertEqual(Set(drone.map { $0.midi % 12 }), [9, 4])
        XCTAssertEqual(KeyReference.frequency(midi: 69), 440, accuracy: 1e-9)
        XCTAssertEqual(KeyReference.gain(at: 0, duration: 2), 0, accuracy: 1e-9)
        XCTAssertEqual(KeyReference.gain(at: 2, duration: 2), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(KeyReference.gain(at: 0.5, duration: 2), 0.3)
    }
}
