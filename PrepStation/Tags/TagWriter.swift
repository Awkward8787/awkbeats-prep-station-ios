import Foundation
import AVFoundation

/// Writes producer metadata into the audio file's real tags (same layout as the desktop `TagWriter.ts`):
/// ID3v2 for MP3, a RIFF INFO list plus an `id3 ` chunk for WAV, NAME/AUTH plus an `ID3 ` chunk for AIFF,
/// Vorbis comments plus a PICTURE block for FLAC, and iTunes atoms for M4A.
/// The audio data itself is copied byte for byte.
enum TagWriter {
    static func write(_ payload: TagPayload, to url: URL, format: AudioFormat) async throws {
        switch format {
        case .m4a:
            try await writeM4A(payload, to: url)
        default:
            let original = try Data(contentsOf: url)
            let updated = try rewrite(original, format: format, payload: payload)
            try updated.write(to: url, options: .atomic)
        }
    }

    /// Pure function used by the app and the tests.
    static func rewrite(_ data: Data, format: AudioFormat, payload: TagPayload) throws -> Data {
        switch format {
        case .mp3: return rewriteMP3(data, payload)
        case .wav: return try rewriteWAV(data, payload)
        case .aiff: return try rewriteAIFF(data, payload)
        case .flac: return try rewriteFLAC(data, payload)
        case .m4a: throw TagError.exportFailed("M4A uses the async writer")
        }
    }

    // MARK: MP3

    static func rewriteMP3(_ data: Data, _ p: TagPayload) -> Data {
        let skip = ID3.leadingTagLength(data)
        return ID3.makeTag(p) + data.sub(skip, data.count)
    }

    // MARK: RIFF / AIFF chunks

    struct Chunk { var id: String; var data: Data }

    static func readChunks(_ d: Data, littleEndian: Bool) throws -> [Chunk] {
        var chunks: [Chunk] = []
        var offset = 12
        while offset + 8 <= d.count {
            let id = d.ascii(offset, 4)
            let size = Int(littleEndian ? d.u32le(offset + 4) : d.u32be(offset + 4))
            let start = offset + 8
            // Some encoders write a data chunk size larger than the file; keep what is there.
            let end = min(d.count, start + size)
            chunks.append(Chunk(id: id, data: d.sub(start, end)))
            offset = start + size + (size % 2)
        }
        return chunks
    }

    static func pack(form: String, _ chunks: [Chunk], littleEndian: Bool) -> Data {
        var body = Data()
        for c in chunks {
            body.appendASCII(c.id)
            if littleEndian { body.appendU32le(UInt32(c.data.count)) } else { body.appendU32be(UInt32(c.data.count)) }
            body.append(c.data)
            if c.data.count % 2 == 1 { body.append(0) }
        }
        var out = Data(littleEndian ? "RIFF".utf8 : "FORM".utf8)
        if littleEndian { out.appendU32le(UInt32(4 + body.count)) } else { out.appendU32be(UInt32(4 + body.count)) }
        out.appendASCII(form)
        out.append(body)
        return out
    }

    static func rewriteWAV(_ d: Data, _ p: TagPayload) throws -> Data {
        guard d.count >= 12, d.ascii(0, 4) == "RIFF", d.ascii(8, 4) == "WAVE" else { throw TagError.notFormat("WAV") }
        var kept = try readChunks(d, littleEndian: true).filter { c in
            if c.id == "id3 " || c.id == "ID3 " { return false }
            if c.id == "LIST" && c.data.ascii(0, 4) == "INFO" { return false }
            return true
        }
        guard kept.contains(where: { $0.id == "data" }) else { throw TagError.corrupt("audio data") }
        kept.append(listInfo(p))
        kept.append(Chunk(id: "id3 ", data: ID3.makeTag(p, padding: 0)))
        return pack(form: "WAVE", kept, littleEndian: true)
    }

    static func listInfo(_ p: TagPayload) -> Chunk {
        let entries: [(String, String)] = [
            ("INAM", p.title), ("IART", p.artist), ("IPRO", p.producer), ("IGNR", p.genre),
            ("ICMT", p.comment), ("IKEY", p.key?.name ?? ""), ("IBPM", p.bpm.map(BpmMath.format) ?? ""),
        ]
        var d = Data("INFO".utf8)
        for (id, value) in entries where !value.isEmpty {
            var v = Data(value.utf8); v.append(0)
            d.appendASCII(id); d.appendU32le(UInt32(v.count)); d.append(v)
            if v.count % 2 == 1 { d.append(0) }
        }
        return Chunk(id: "LIST", data: d)
    }

    static func rewriteAIFF(_ d: Data, _ p: TagPayload) throws -> Data {
        guard d.count >= 12, d.ascii(0, 4) == "FORM" else { throw TagError.notFormat("AIFF") }
        let form = d.ascii(8, 4)
        guard form == "AIFF" || form == "AIFC" else { throw TagError.notFormat("AIFF") }
        let drop: Set<String> = ["NAME", "AUTH", "ANNO", "ID3 ", "id3 "]
        var kept = try readChunks(d, littleEndian: false).filter { !drop.contains($0.id) }
        guard kept.contains(where: { $0.id == "SSND" }) else { throw TagError.corrupt("audio data") }
        if !p.title.isEmpty { kept.append(Chunk(id: "NAME", data: Data(p.title.utf8))) }
        if !p.artist.isEmpty { kept.append(Chunk(id: "AUTH", data: Data(p.artist.utf8))) }
        kept.append(Chunk(id: "ID3 ", data: ID3.makeTag(p, padding: 0)))
        return pack(form: form, kept, littleEndian: false)
    }

    // MARK: FLAC

    struct Block { var type: UInt8; var data: Data }

    static func readFLAC(_ d: Data) throws -> (blocks: [Block], audioStart: Int) {
        guard d.count >= 4, d.ascii(0, 4) == "fLaC" else { throw TagError.notFormat("FLAC") }
        var blocks: [Block] = []
        var offset = 4
        while offset + 4 <= d.count {
            let header = d.byte(offset)
            let size = Int(d.byte(offset + 1)) << 16 | Int(d.byte(offset + 2)) << 8 | Int(d.byte(offset + 3))
            let start = offset + 4, end = start + size
            guard end <= d.count else { throw TagError.corrupt("FLAC metadata") }
            blocks.append(Block(type: header & 0x7F, data: d.sub(start, end)))
            offset = end
            if header & 0x80 != 0 { return (blocks, offset) }
        }
        throw TagError.corrupt("FLAC metadata")
    }

    static func rewriteFLAC(_ d: Data, _ p: TagPayload) throws -> Data {
        let parsed = try readFLAC(d)
        guard parsed.blocks.first?.type == 0 else { throw TagError.corrupt("FLAC stream info") }
        var blocks = parsed.blocks.filter { $0.type != 4 && $0.type != 6 && $0.type != 1 }
        blocks.append(Block(type: 4, data: vorbisComment(p)))
        if let art = p.artwork { blocks.append(Block(type: 6, data: flacPicture(art))) }
        blocks.append(Block(type: 1, data: Data(count: 1024)))
        var out = Data("fLaC".utf8)
        for (i, b) in blocks.enumerated() {
            let last: UInt8 = i == blocks.count - 1 ? 0x80 : 0
            out.append(contentsOf: [last | b.type, UInt8((b.data.count >> 16) & 0xFF), UInt8((b.data.count >> 8) & 0xFF), UInt8(b.data.count & 0xFF)])
            out.append(b.data)
        }
        out.append(d.sub(parsed.audioStart, d.count))
        return out
    }

    static func vorbisPairs(_ p: TagPayload) -> [(String, String)] {
        [
            ("TITLE", p.title), ("ARTIST", p.artist), ("COMPOSER", p.producer), ("PRODUCER", p.producer),
            ("GENRE", p.genre), ("COMMENT", p.comment),
            ("BPM", p.bpm.map(BpmMath.format) ?? ""),
            ("KEY", p.key?.name ?? ""), ("INITIALKEY", p.key?.camelot ?? ""), ("CAMELOT", p.key?.camelot ?? ""),
        ].filter { !$0.1.isEmpty }
    }

    static func vorbisComment(_ p: TagPayload) -> Data {
        let vendor = Data("AwkBeats Prep Station".utf8)
        let pairs = vorbisPairs(p)
        var d = Data()
        d.appendU32le(UInt32(vendor.count)); d.append(vendor)
        d.appendU32le(UInt32(pairs.count))
        for (k, v) in pairs {
            let line = Data("\(k)=\(v)".utf8)
            d.appendU32le(UInt32(line.count)); d.append(line)
        }
        return d
    }

    static func flacPicture(_ art: Artwork) -> Data {
        var d = Data()
        let mime = Data(art.mime.utf8), desc = Data("Cover".utf8)
        d.appendU32be(3)
        d.appendU32be(UInt32(mime.count)); d.append(mime)
        d.appendU32be(UInt32(desc.count)); d.append(desc)
        d.appendU32be(UInt32(art.width)); d.appendU32be(UInt32(art.height)); d.appendU32be(24); d.appendU32be(0)
        d.appendU32be(UInt32(art.data.count)); d.append(art.data)
        return d
    }

    // MARK: M4A

    static func writeM4A(_ p: TagPayload, to url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw TagError.exportFailed("this M4A can't be re-wrapped")
        }
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".tagging-\(UUID().uuidString).m4a")
        session.outputURL = tmp
        session.outputFileType = .m4a
        session.metadata = m4aItems(p)
        await session.export()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: tmp)
            throw TagError.exportFailed(session.error?.localizedDescription ?? "export did not finish")
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    static func m4aItems(_ p: TagPayload) -> [AVMetadataItem] {
        func item(_ id: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol, dataType: String? = nil) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = id
            m.value = value
            if let dataType { m.dataType = dataType }
            return m
        }
        var items: [AVMetadataItem] = []
        if !p.title.isEmpty { items.append(item(.iTunesMetadataSongName, p.title as NSString)) }
        if !p.artist.isEmpty { items.append(item(.iTunesMetadataArtist, p.artist as NSString)) }
        if !p.producer.isEmpty { items.append(item(.iTunesMetadataComposer, p.producer as NSString)) }
        if !p.genre.isEmpty { items.append(item(.iTunesMetadataUserGenre, p.genre as NSString)) }
        if let bpm = p.bpm {
            items.append(item(.iTunesMetadataBeatsPerMin, NSNumber(value: Int16(bpm.rounded())),
                              dataType: kCMMetadataBaseDataType_SInt16 as String))
        }
        var comment = p.comment
        if let key = p.key {
            let line = "Key: \(key.name) (\(key.camelot))"
            comment = comment.isEmpty ? line : "\(line)\n\(comment)"
        }
        if !comment.isEmpty { items.append(item(.iTunesMetadataUserComment, comment as NSString)) }
        if let art = p.artwork {
            items.append(item(.iTunesMetadataCoverArt, art.data as NSData,
                              dataType: (art.mime == "image/png" ? kCMMetadataBaseDataType_PNG : kCMMetadataBaseDataType_JPEG) as String))
        }
        return items
    }
}
