import XCTest
import AVFoundation
@testable import PrepStation

final class TagRoundTripTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tagtests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func fixture(_ name: String) throws -> URL {
        let src = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        let dst = tmp.appendingPathComponent(name)
        try FileManager.default.copyItem(at: src, to: dst)
        return dst
    }

    func samplePayload(unicode: Bool = false) -> TagPayload {
        var p = TagPayload()
        p.title = unicode ? "Nuit Blanche — 夜" : "Night Drive"
        p.artist = unicode ? "Zoë" : "Kaia Moon"
        p.producer = "Awkward J"
        p.genre = "Trap"
        p.bpm = 140
        p.key = Camelot.parse("F# minor")
        let jpeg = DemoArtworkForTests.jpeg()
        let s = ImageInfo.size(of: jpeg)
        p.artwork = Artwork(data: jpeg, mime: "image/jpeg", width: s.0, height: s.1)
        return p
    }

    func assertSame(_ a: TagPayload, _ b: TagPayload, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.title, b.title, file: file, line: line)
        XCTAssertEqual(a.artist, b.artist, file: file, line: line)
        XCTAssertEqual(a.producer, b.producer, file: file, line: line)
        XCTAssertEqual(a.genre, b.genre, file: file, line: line)
        XCTAssertEqual(a.bpm, b.bpm, file: file, line: line)
        XCTAssertEqual(a.key, b.key, file: file, line: line)
        XCTAssertEqual(a.artwork?.data, b.artwork?.data, "artwork bytes", file: file, line: line)
    }

    /// Writes tags, reads them back, and checks the audio still decodes to the same frames.
    func roundTrip(_ name: String, format: AudioFormat, unicode: Bool = false) async throws {
        let url = try fixture(name)
        let before = try AVAudioFile(forReading: url).length
        let payload = samplePayload(unicode: unicode)
        try await TagWriter.write(payload, to: url, format: format)
        let back = await TagReader.read(url: url, format: format)
        assertSame(payload, back)
        let after = try AVAudioFile(forReading: url)
        XCTAssertEqual(after.length, before, "\(name) audio length changed")
        // Writing twice must replace, not stack, the tags.
        var second = payload; second.title = "Second Pass"; second.bpm = 93.5
        try await TagWriter.write(second, to: url, format: format)
        let back2 = await TagReader.read(url: url, format: format)
        XCTAssertEqual(back2.title, "Second Pass")
        if format != .m4a { XCTAssertEqual(back2.bpm, 93.5) } // iTunes tmpo is an integer
        XCTAssertEqual(try AVAudioFile(forReading: url).length, before)
    }

    func testMP3() async throws { try await roundTrip("beat01.mp3", format: .mp3) }
    func testMP3Unicode() async throws { try await roundTrip("beat05.mp3", format: .mp3, unicode: true) }
    func testWAV() async throws { try await roundTrip("beat02.wav", format: .wav) }
    func testWAVUnicode() async throws { try await roundTrip("beat06.wav", format: .wav, unicode: true) }
    func testFLAC() async throws { try await roundTrip("beat03.flac", format: .flac) }
    func testAIFF() async throws { try await roundTrip("beat09.aiff", format: .aiff) }

    func testM4A() async throws {
        let url = try fixture("beat04.m4a")
        let before = try AVAudioFile(forReading: url).length
        let payload = samplePayload()
        try await TagWriter.write(payload, to: url, format: .m4a)
        let back = await TagReader.read(url: url, format: .m4a)
        XCTAssertEqual(back.title, payload.title)
        XCTAssertEqual(back.artist, payload.artist)
        XCTAssertEqual(back.producer, payload.producer)
        XCTAssertEqual(back.genre, payload.genre)
        XCTAssertEqual(back.bpm, 140)
        XCTAssertEqual(back.key, payload.key)
        XCTAssertNotNil(back.artwork)
        XCTAssertEqual(try AVAudioFile(forReading: url).length, before)
    }

    func testMP3AudioBytesUntouched() throws {
        let url = try fixture("beat08.mp3")
        let original = try Data(contentsOf: url)
        let audio = original.sub(ID3.leadingTagLength(original), original.count)
        let tagged = TagWriter.rewriteMP3(original, samplePayload())
        XCTAssertEqual(tagged.sub(ID3.leadingTagLength(tagged), tagged.count), audio)
        let retagged = TagWriter.rewriteMP3(tagged, TagPayload(title: "x"))
        XCTAssertEqual(retagged.sub(ID3.leadingTagLength(retagged), retagged.count), audio)
    }

    func testID3FrameLayout() {
        var p = TagPayload(); p.title = "Hi"; p.bpm = 102.75; p.key = Camelot.parse("Am")
        let tag = ID3.makeTag(p, padding: 0)
        XCTAssertEqual(tag.ascii(0, 3), "ID3")
        XCTAssertEqual(tag.byte(3), 3)
        let read = ID3.read(tag)!
        XCTAssertEqual(read.title, "Hi")
        XCTAssertEqual(read.bpm, 102.75)
        XCTAssertEqual(read.key, Camelot.parse("A minor"))
        // TKEY uses the 3-character form.
        XCTAssertNotNil(tag.range(of: Data("TKEY".utf8)))
        XCTAssertNotNil(tag.range(of: Data("Am".utf8)))
    }

    func testRejectsWrongContainer() {
        XCTAssertThrowsError(try TagWriter.rewrite(Data("not audio at all".utf8), format: .wav, payload: TagPayload()))
        XCTAssertThrowsError(try TagWriter.rewrite(Data("not audio at all".utf8), format: .flac, payload: TagPayload()))
        XCTAssertThrowsError(try TagWriter.rewrite(Data("not audio at all".utf8), format: .aiff, payload: TagPayload()))
    }

    func testArtworkNormalizedToSquare() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 250))
        let img = renderer.image { c in UIColor.purple.setFill(); c.fill(CGRect(x: 0, y: 0, width: 400, height: 250)) }
        let jpeg = try XCTUnwrap(ArtworkProcessor.normalized(img))
        let s = ImageInfo.size(of: jpeg)
        XCTAssertEqual(s.0, s.1)
        XCTAssertGreaterThan(s.0, 0)
    }
}

enum DemoArtworkForTests {
    static func jpeg() -> Data { DemoLibrary.artwork(1)! }
}
