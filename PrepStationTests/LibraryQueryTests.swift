import XCTest
import SwiftData
@testable import PrepStation

@MainActor
final class LibraryQueryTests: XCTestCase {
    func makeBeats() throws -> (ModelContainer, [Beat]) {
        let container = try ModelContainer(for: Beat.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        func beat(_ title: String, _ key: String, _ bpm: Double, _ status: BeatStatus, artist: String = "", ago: Double) -> Beat {
            let b = Beat(fileName: "\(title).wav", format: .wav, fileSize: 1, title: title, producer: "Awkward J")
            b.keyDetected = key; b.bpmDetected = bpm; b.status = status; b.artist = artist
            b.importedAt = Date().addingTimeInterval(-ago)
            ctx.insert(b); return b
        }
        let beats = [
            beat("Gold Hour", "A minor", 92, .ready, artist: "Kaia Moon", ago: 10),
            beat("Night Drive", "F# minor", 140, .inProgress, ago: 20),
            beat("Alley Light", "D minor", 88, .ready, ago: 30),
        ]
        return (container, beats)
    }

    func testSearchByTitleArtistKeyBpm() throws {
        let (_, beats) = try makeBeats()
        XCTAssertEqual(LibraryQuery.apply(beats, search: "gold", status: nil, sort: .recent).map(\.title), ["Gold Hour"])
        XCTAssertEqual(LibraryQuery.apply(beats, search: "kaia", status: nil, sort: .recent).map(\.title), ["Gold Hour"])
        XCTAssertEqual(LibraryQuery.apply(beats, search: "11A", status: nil, sort: .recent).map(\.title), ["Night Drive"])
        XCTAssertEqual(LibraryQuery.apply(beats, search: "140", status: nil, sort: .recent).map(\.title), ["Night Drive"])
        XCTAssertEqual(LibraryQuery.apply(beats, search: "minor ready", status: nil, sort: .title).map(\.title), ["Alley Light", "Gold Hour"])
    }

    func testStatusFilterAndSort() throws {
        let (_, beats) = try makeBeats()
        XCTAssertEqual(LibraryQuery.apply(beats, search: "", status: .ready, sort: .bpm).map(\.title), ["Alley Light", "Gold Hour"])
        XCTAssertEqual(LibraryQuery.apply(beats, search: "", status: nil, sort: .recent).map(\.title), ["Gold Hour", "Night Drive", "Alley Light"])
        // Camelot order: 7A (D minor), 8A (A minor), 11A (F# minor)
        XCTAssertEqual(LibraryQuery.apply(beats, search: "", status: nil, sort: .key).map(\.title), ["Alley Light", "Gold Hour", "Night Drive"])
    }

    func testOverridesWin() throws {
        let (_, beats) = try makeBeats()
        let b = beats[1]
        b.bpmScale = 0.5
        XCTAssertEqual(b.workingBpm, 70)
        b.bpmOverride = 141
        XCTAssertEqual(b.workingBpm, 141)
        b.keyOverride = "8B"
        XCTAssertEqual(b.workingKey?.name, "C major")
        XCTAssertEqual(b.payload.key?.camelot, "8B")
        XCTAssertEqual(b.payload.producer, "Awkward J")
    }
}
