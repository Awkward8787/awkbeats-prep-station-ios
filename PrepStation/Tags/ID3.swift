import Foundation

/// Minimal ID3v2.3 writer and v2.3/v2.4 reader for the frames Prep Station uses.
/// Text is ISO-8859-1 when it fits, otherwise UTF-16 with a BOM (the v2.3 rules).
enum ID3 {
    // MARK: Write

    static func makeTag(_ p: TagPayload, padding: Int = 1024) -> Data {
        var frames = Data()
        func text(_ id: String, _ value: String) {
            guard !value.isEmpty else { return }
            frames.append(frame(id, encodedText(value)))
        }
        text("TIT2", p.title)
        text("TPE1", p.artist)
        text("TCOM", p.producer)
        text("TCON", p.genre)
        if let bpm = p.bpm { text("TBPM", BpmMath.format(bpm)) }
        if let key = p.key {
            text("TKEY", key.shortName)
            frames.append(frame("TXXX", userText("KEY", key.name)))
            frames.append(frame("TXXX", userText("CAMELOT", key.camelot)))
        }
        if !p.producer.isEmpty {
            frames.append(frame("TXXX", userText("PRODUCER", p.producer)))
            // v2.3 involved-people list: role, name.
            frames.append(frame("IPLS", encodedPairs(["producer", p.producer])))
        }
        if !p.comment.isEmpty {
            let (enc, body) = encode(p.comment)
            var d = Data([enc]); d.appendASCII("eng"); d.append(terminator(enc)); d.append(body)
            frames.append(frame("COMM", d))
        }
        if let art = p.artwork {
            var d = Data([0]); d.appendASCII(art.mime); d.append(0); d.append(3) // front cover
            d.appendASCII("Cover"); d.append(0); d.append(art.data)
            frames.append(frame("APIC", d))
        }
        var tag = Data("ID3".utf8)
        tag.append(contentsOf: [3, 0, 0])
        tag.append(syncsafe(frames.count + padding))
        tag.append(frames)
        tag.append(Data(count: padding))
        return tag
    }

    static func frame(_ id: String, _ body: Data) -> Data {
        var d = Data(id.utf8)
        d.appendU32be(UInt32(body.count))
        d.append(contentsOf: [0, 0])
        d.append(body)
        return d
    }

    static func syncsafe(_ v: Int) -> Data {
        Data([UInt8((v >> 21) & 0x7F), UInt8((v >> 14) & 0x7F), UInt8((v >> 7) & 0x7F), UInt8(v & 0x7F)])
    }

    static func unsyncsafe(_ d: Data, _ at: Int) -> Int {
        Int(d.byte(at) & 0x7F) << 21 | Int(d.byte(at + 1) & 0x7F) << 14 | Int(d.byte(at + 2) & 0x7F) << 7 | Int(d.byte(at + 3) & 0x7F)
    }

    /// (encoding byte, encoded bytes without terminator)
    static func encode(_ s: String) -> (UInt8, Data) {
        if let latin = s.data(using: .isoLatin1) { return (0, latin) }
        var d = Data([0xFF, 0xFE])
        d.append(s.data(using: .utf16LittleEndian) ?? Data())
        return (1, d)
    }

    static func terminator(_ enc: UInt8) -> Data { enc == 0 || enc == 3 ? Data([0]) : Data([0, 0]) }

    static func encodedText(_ s: String) -> Data {
        let (enc, body) = encode(s)
        return Data([enc]) + body
    }

    static func userText(_ description: String, _ value: String) -> Data {
        let needsWide = description.data(using: .isoLatin1) == nil || value.data(using: .isoLatin1) == nil
        if needsWide {
            var d = Data([1])
            for (i, part) in [description, value].enumerated() {
                d.append(contentsOf: [0xFF, 0xFE]); d.append(part.data(using: .utf16LittleEndian) ?? Data())
                if i == 0 { d.append(contentsOf: [0, 0]) }
            }
            return d
        }
        var d = Data([0]); d.append(description.data(using: .isoLatin1)!); d.append(0); d.append(value.data(using: .isoLatin1)!)
        return d
    }

    static func encodedPairs(_ parts: [String]) -> Data {
        let wide = parts.contains { $0.data(using: .isoLatin1) == nil }
        var d = Data([wide ? 1 : 0])
        for part in parts {
            if wide { d.append(contentsOf: [0xFF, 0xFE]); d.append(part.data(using: .utf16LittleEndian) ?? Data()); d.append(contentsOf: [0, 0]) }
            else { d.append(part.data(using: .isoLatin1)!); d.append(0) }
        }
        return d
    }

    /// Byte length of the ID3v2 tag(s) at the start of `data` (0 if none).
    static func leadingTagLength(_ data: Data) -> Int {
        var offset = 0
        while data.count >= offset + 10, data.ascii(offset, 3) == "ID3" {
            let flags = data.byte(offset + 5)
            let size = unsyncsafe(data, offset + 6)
            offset += 10 + size + ((flags & 0x10) != 0 ? 10 : 0)
        }
        return min(offset, data.count)
    }

    // MARK: Read

    static func read(_ data: Data) -> TagPayload? {
        guard data.count >= 10, data.ascii(0, 3) == "ID3" else { return nil }
        let version = data.byte(3)
        guard version == 3 || version == 4 else { return nil }
        let flags = data.byte(5)
        let size = unsyncsafe(data, 6)
        let end = min(data.count, 10 + size)
        var offset = 10
        if flags & 0x40 != 0 { // extended header
            let ext = version == 4 ? unsyncsafe(data, 10) : Int(data.u32be(10)) + 4
            offset += ext
        }
        var p = TagPayload()
        var txxx: [String: String] = [:]
        var tkey: String?
        while offset + 10 <= end {
            let id = data.ascii(offset, 4)
            guard id.first?.isLetter == true || id.first?.isNumber == true, id != "\0\0\0\0" else { break }
            let fsize = version == 4 ? unsyncsafe(data, offset + 4) : Int(data.u32be(offset + 4))
            let bodyStart = offset + 10, bodyEnd = bodyStart + fsize
            guard fsize >= 0, bodyEnd <= end else { break }
            let body = data.sub(bodyStart, bodyEnd)
            switch id {
            case "TIT2": p.title = decodeText(body)
            case "TPE1": p.artist = decodeText(body)
            case "TCOM": p.producer = decodeText(body)
            case "TCON": p.genre = decodeText(body)
            case "TBPM": p.bpm = Double(decodeText(body).trimmingCharacters(in: .whitespaces))
            case "TKEY": tkey = decodeText(body)
            case "TXXX":
                let parts = splitStrings(body)
                if parts.count >= 2 { txxx[parts[0].uppercased()] = parts[1] }
            case "COMM":
                if body.count > 4 {
                    let enc = body.byte(0)
                    let parts = splitStrings(Data([enc]) + body.sub(4, body.count))
                    p.comment = parts.count >= 2 ? parts[1] : (parts.first ?? "")
                }
            case "APIC": p.artwork = decodeAPIC(body)
            default: break
            }
            offset = bodyEnd
        }
        if p.producer.isEmpty, let prod = txxx["PRODUCER"] { p.producer = prod }
        p.key = Camelot.parse(txxx["KEY"]) ?? Camelot.parse(txxx["CAMELOT"]) ?? Camelot.parse(tkey)
        return p
    }

    static func decodeText(_ body: Data) -> String {
        guard body.count >= 1 else { return "" }
        return splitStrings(body).first ?? ""
    }

    /// Splits an encoded body (first byte = encoding) into its null-separated strings.
    static func splitStrings(_ body: Data) -> [String] {
        guard body.count >= 1 else { return [] }
        let enc = body.byte(0)
        let bytes = body.sub(1, body.count)
        var out: [String] = []
        if enc == 1 || enc == 2 {
            var i = 0, start = 0
            let arr = [UInt8](bytes)
            while i + 1 < arr.count {
                if arr[i] == 0 && arr[i + 1] == 0 { out.append(decodeWide(Data(arr[start..<i]), enc)); start = i + 2 }
                i += 2
            }
            if start < arr.count { out.append(decodeWide(Data(arr[start..<arr.count]), enc)) }
        } else {
            for part in bytes.split(separator: 0, omittingEmptySubsequences: false) {
                out.append(enc == 3 ? String(decoding: part, as: UTF8.self) : (String(data: Data(part), encoding: .isoLatin1) ?? ""))
            }
            while out.count > 1, out.last == "" { out.removeLast() }
        }
        return out
    }

    static func decodeWide(_ d: Data, _ enc: UInt8) -> String {
        if d.count >= 2 && d.byte(0) == 0xFF && d.byte(1) == 0xFE { return String(data: d.sub(2, d.count), encoding: .utf16LittleEndian) ?? "" }
        if d.count >= 2 && d.byte(0) == 0xFE && d.byte(1) == 0xFF { return String(data: d.sub(2, d.count), encoding: .utf16BigEndian) ?? "" }
        return String(data: d, encoding: enc == 2 ? .utf16BigEndian : .utf16LittleEndian) ?? ""
    }

    static func decodeAPIC(_ body: Data) -> Artwork? {
        guard body.count > 4 else { return nil }
        let enc = body.byte(0)
        let arr = [UInt8](body)
        guard let mimeEnd = arr[1...].firstIndex(of: 0) else { return nil }
        let mime = String(decoding: arr[1..<mimeEnd], as: UTF8.self)
        var i = mimeEnd + 2 // skip null + picture type
        // Skip description.
        if enc == 1 || enc == 2 {
            while i + 1 < arr.count, !(arr[i] == 0 && arr[i + 1] == 0) { i += 2 }
            i += 2
        } else {
            while i < arr.count, arr[i] != 0 { i += 1 }
            i += 1
        }
        guard i < arr.count else { return nil }
        let img = Data(arr[i...])
        let resolved = mime.contains("png") || mime.uppercased() == "PNG" ? "image/png" : "image/jpeg"
        let size = ImageInfo.size(of: img)
        return Artwork(data: img, mime: resolved, width: size.0, height: size.1)
    }
}

/// Reads pixel dimensions from PNG / JPEG headers without decoding the image.
enum ImageInfo {
    static func size(of d: Data) -> (Int, Int) {
        if d.count > 24, d.byte(0) == 0x89, d.ascii(1, 3) == "PNG" {
            return (Int(d.u32be(16)), Int(d.u32be(20)))
        }
        guard d.count > 4, d.byte(0) == 0xFF, d.byte(1) == 0xD8 else { return (0, 0) }
        var i = 2
        while i + 9 < d.count {
            guard d.byte(i) == 0xFF else { i += 1; continue }
            let marker = d.byte(i + 1)
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            let len = Int(d.byte(i + 2)) << 8 | Int(d.byte(i + 3))
            if (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC {
                let h = Int(d.byte(i + 5)) << 8 | Int(d.byte(i + 6))
                let w = Int(d.byte(i + 7)) << 8 | Int(d.byte(i + 8))
                return (w, h)
            }
            i += 2 + len
        }
        return (0, 0)
    }
}
