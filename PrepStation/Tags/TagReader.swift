import Foundation
import AVFoundation

/// Reads the tags Prep Station cares about. Used on import (to keep what the producer already tagged)
/// and by the round-trip tests.
enum TagReader {
    static func read(url: URL, format: AudioFormat) async -> TagPayload {
        if format == .m4a { return await readM4A(url) }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return TagPayload() }
        return read(data, format: format)
    }

    static func read(_ d: Data, format: AudioFormat) -> TagPayload {
        switch format {
        case .mp3: return ID3.read(d) ?? TagPayload()
        case .wav: return readRIFF(d)
        case .aiff: return readAIFF(d)
        case .flac: return readFLAC(d)
        case .m4a: return TagPayload()
        }
    }

    static func readRIFF(_ d: Data) -> TagPayload {
        guard d.count >= 12, d.ascii(0, 4) == "RIFF", let chunks = try? TagWriter.readChunks(d, littleEndian: true) else { return TagPayload() }
        if let id3 = chunks.first(where: { $0.id == "id3 " || $0.id == "ID3 " }), let p = ID3.read(id3.data) { return p }
        var p = TagPayload()
        if let list = chunks.first(where: { $0.id == "LIST" && $0.data.ascii(0, 4) == "INFO" }) {
            let info = list.data
            var o = 4
            while o + 8 <= info.count {
                let id = info.ascii(o, 4), size = Int(info.u32le(o + 4))
                let raw = info.sub(o + 8, o + 8 + size)
                let value = String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                switch id {
                case "INAM": p.title = value
                case "IART": p.artist = value
                case "IPRO": p.producer = value
                case "IGNR": p.genre = value
                case "ICMT": p.comment = value
                case "IKEY": p.key = Camelot.parse(value)
                case "IBPM": p.bpm = Double(value)
                default: break
                }
                o += 8 + size + (size % 2)
            }
        }
        return p
    }

    static func readAIFF(_ d: Data) -> TagPayload {
        guard d.count >= 12, d.ascii(0, 4) == "FORM", let chunks = try? TagWriter.readChunks(d, littleEndian: false) else { return TagPayload() }
        if let id3 = chunks.first(where: { $0.id == "ID3 " || $0.id == "id3 " }), let p = ID3.read(id3.data) { return p }
        var p = TagPayload()
        if let n = chunks.first(where: { $0.id == "NAME" }) { p.title = String(decoding: n.data, as: UTF8.self) }
        if let a = chunks.first(where: { $0.id == "AUTH" }) { p.artist = String(decoding: a.data, as: UTF8.self) }
        return p
    }

    static func readFLAC(_ d: Data) -> TagPayload {
        guard let parsed = try? TagWriter.readFLAC(d) else { return TagPayload() }
        var p = TagPayload()
        if let vc = parsed.blocks.first(where: { $0.type == 4 })?.data {
            var o = 0
            let vendorLen = Int(vc.u32le(o)); o += 4 + vendorLen
            let n = Int(vc.u32le(o)); o += 4
            var fields: [String: String] = [:]
            for _ in 0..<n where o + 4 <= vc.count {
                let len = Int(vc.u32le(o)); o += 4
                let line = String(decoding: vc.sub(o, o + len), as: UTF8.self); o += len
                if let eq = line.firstIndex(of: "=") {
                    let k = line[..<eq].uppercased()
                    if fields[k] == nil { fields[k] = String(line[line.index(after: eq)...]) }
                }
            }
            p.title = fields["TITLE"] ?? ""
            p.artist = fields["ARTIST"] ?? ""
            p.producer = fields["PRODUCER"] ?? fields["COMPOSER"] ?? ""
            p.genre = fields["GENRE"] ?? ""
            p.comment = fields["COMMENT"] ?? fields["DESCRIPTION"] ?? ""
            p.bpm = fields["BPM"].flatMap(Double.init) ?? fields["TBPM"].flatMap(Double.init)
            p.key = Camelot.parse(fields["KEY"]) ?? Camelot.parse(fields["INITIALKEY"]) ?? Camelot.parse(fields["CAMELOT"])
        }
        if let pic = parsed.blocks.first(where: { $0.type == 6 })?.data, pic.count > 32 {
            var o = 4
            let mimeLen = Int(pic.u32be(o)); o += 4
            let mime = pic.ascii(o, mimeLen); o += mimeLen
            let descLen = Int(pic.u32be(o)); o += 4 + descLen
            let w = Int(pic.u32be(o)), h = Int(pic.u32be(o + 4)); o += 16
            let len = Int(pic.u32be(o)); o += 4
            let img = pic.sub(o, o + len)
            if !img.isEmpty { p.artwork = Artwork(data: img, mime: mime.isEmpty ? "image/jpeg" : mime, width: w, height: h) }
        }
        return p
    }

    static func readM4A(_ url: URL) async -> TagPayload {
        let asset = AVURLAsset(url: url)
        var p = TagPayload()
        guard let items = try? await asset.loadMetadata(for: .iTunesMetadata) else { return p }
        for item in items {
            guard let id = item.identifier else { continue }
            switch id {
            case .iTunesMetadataSongName: p.title = (try? await item.load(.stringValue)) ?? ""
            case .iTunesMetadataArtist: p.artist = (try? await item.load(.stringValue)) ?? ""
            case .iTunesMetadataComposer: p.producer = (try? await item.load(.stringValue)) ?? ""
            case .iTunesMetadataUserGenre: p.genre = (try? await item.load(.stringValue)) ?? ""
            case .iTunesMetadataBeatsPerMin:
                if let n = try? await item.load(.numberValue) { p.bpm = n.doubleValue }
            case .iTunesMetadataUserComment:
                let text = (try? await item.load(.stringValue)) ?? ""
                var rest: [String] = []
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    if line.hasPrefix("Key: ") {
                        let body = line.dropFirst(5)
                        let name = body.split(separator: "(").first.map { $0.trimmingCharacters(in: .whitespaces) }
                        p.key = Camelot.parse(name)
                    } else { rest.append(String(line)) }
                }
                p.comment = rest.joined(separator: "\n")
            case .iTunesMetadataCoverArt:
                if let data = try? await item.load(.dataValue) {
                    let s = ImageInfo.size(of: data)
                    let png = data.first == 0x89
                    p.artwork = Artwork(data: data, mime: png ? "image/png" : "image/jpeg", width: s.0, height: s.1)
                }
            default: break
            }
        }
        return p
    }
}
