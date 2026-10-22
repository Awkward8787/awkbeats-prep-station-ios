import Foundation

struct Artwork: Equatable {
    var data: Data          // JPEG or PNG bytes
    var mime: String        // "image/jpeg" or "image/png"
    var width: Int
    var height: Int
}

/// What Prep Station writes into (and reads back from) an audio file.
struct TagPayload: Equatable {
    var title = ""
    var artist = ""
    var producer = ""
    var genre = ""
    var bpm: Double?
    var key: NamedKey?
    var comment = ""
    var artwork: Artwork?
}

enum AudioFormat: String, Codable, CaseIterable {
    case mp3, wav, aiff, flac, m4a

    init?(fileExtension ext: String) {
        switch ext.lowercased() {
        case "mp3": self = .mp3
        case "wav", "wave": self = .wav
        case "aif", "aiff", "aifc": self = .aiff
        case "flac": self = .flac
        case "m4a", "mp4", "aac": self = .m4a
        default: return nil
        }
    }

    var label: String { rawValue.uppercased() }

    /// Which tag standard Prep Station writes for this format (shown next to the Save button).
    var tagStandard: String {
        switch self {
        case .mp3: return "ID3v2.3"
        case .wav: return "RIFF INFO + ID3"
        case .aiff: return "AIFF + ID3"
        case .flac: return "Vorbis comments"
        case .m4a: return "iTunes metadata"
        }
    }
}

enum TagError: LocalizedError {
    case notFormat(String)
    case corrupt(String)
    case exportFailed(String)
    var errorDescription: String? {
        switch self {
        case .notFormat(let f): return "This isn't a valid \(f) file."
        case .corrupt(let what): return "The file's \(what) looks damaged, so it was left unchanged."
        case .exportFailed(let why): return "Couldn't save tags: \(why)"
        }
    }
}

// MARK: - Byte helpers

extension Data {
    func u32be(_ at: Int) -> UInt32 {
        guard at + 4 <= count else { return 0 }
        let b = self.startIndex + at
        return UInt32(self[b]) << 24 | UInt32(self[b + 1]) << 16 | UInt32(self[b + 2]) << 8 | UInt32(self[b + 3])
    }
    func u32le(_ at: Int) -> UInt32 {
        guard at + 4 <= count else { return 0 }
        let b = self.startIndex + at
        return UInt32(self[b]) | UInt32(self[b + 1]) << 8 | UInt32(self[b + 2]) << 16 | UInt32(self[b + 3]) << 24
    }
    func byte(_ at: Int) -> UInt8 { self[self.startIndex + at] }
    func sub(_ from: Int, _ to: Int) -> Data {
        let lo = Swift.max(0, Swift.min(from, count)), hi = Swift.max(lo, Swift.min(to, count))
        return Data(self[(startIndex + lo)..<(startIndex + hi)])
    }
    func ascii(_ from: Int, _ len: Int) -> String { String(decoding: sub(from, from + len), as: UTF8.self) }

    mutating func appendU32be(_ v: UInt32) { Swift.withUnsafeBytes(of: v.bigEndian) { append(contentsOf: $0) } }
    mutating func appendU32le(_ v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func appendASCII(_ s: String) { append(contentsOf: Array(s.utf8)) }
}
