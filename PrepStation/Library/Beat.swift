import Foundation
import SwiftData

enum BeatStatus: String, Codable, CaseIterable, Identifiable {
    case idea, inProgress = "in_progress", ready, leased, sold
    var id: String { rawValue }
    var label: String {
        switch self {
        case .idea: return "Idea"
        case .inProgress: return "In progress"
        case .ready: return "Ready"
        case .leased: return "Leased"
        case .sold: return "Sold"
        }
    }
}

@Model
final class Beat {
    @Attribute(.unique) var id: UUID
    /// Original file name, kept so the shared file has the name the producer gave it.
    var fileName: String
    var formatRaw: String
    var fileSize: Int
    var durationSec: Double?
    var sampleRate: Double?

    var title: String
    var producer: String
    var artist: String
    var genre: String
    var notes: String
    var statusRaw: String

    var bpmDetected: Double?
    var bpmConfidence: Double?
    /// 0.5, 1 or 2 (half-time / detected / double-time).
    var bpmScale: Double
    var bpmOverride: Double?

    var keyDetected: String?      // "A minor"
    var keyConfidence: Double?
    var keyOverride: String?

    var hasArtwork: Bool
    var artworkVersion: Int
    var peaks: [Float]

    /// True after a change that "Save tags to file" would put in the audio file.
    var tagsDirty: Bool
    var tagsSavedAt: Date?
    var analysisState: String     // "pending", "done", "failed"
    var importedAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), fileName: String, format: AudioFormat, fileSize: Int, title: String, producer: String) {
        self.id = id
        self.fileName = fileName
        self.formatRaw = format.rawValue
        self.fileSize = fileSize
        self.title = title
        self.producer = producer
        self.artist = ""
        self.genre = ""
        self.notes = ""
        self.statusRaw = BeatStatus.idea.rawValue
        self.bpmScale = 1
        self.hasArtwork = false
        self.artworkVersion = 0
        self.peaks = []
        self.tagsDirty = true
        self.analysisState = "pending"
        self.importedAt = Date()
        self.updatedAt = Date()
    }

    var format: AudioFormat { AudioFormat(rawValue: formatRaw) ?? .wav }
    var status: BeatStatus {
        get { BeatStatus(rawValue: statusRaw) ?? .idea }
        set { statusRaw = newValue.rawValue }
    }

    var workingBpm: Double? { BpmMath.working(detected: bpmDetected, scale: bpmScale, override: bpmOverride) }
    var workingKey: NamedKey? { Camelot.parse(keyOverride) ?? Camelot.parse(keyDetected) }
    var keyNeedsReview: Bool {
        keyOverride == nil && (keyConfidence.map { $0 < KeyEstimate.reviewAt } ?? false)
    }
    var isAnalyzing: Bool { analysisState == "pending" }

    var displayTitle: String { title.isEmpty ? (fileName as NSString).deletingPathExtension : title }

    var fileURL: URL { BeatFiles.audioURL(id: id, fileName: fileName) }
    var artworkURL: URL { BeatFiles.artworkURL(id: id) }

    var payload: TagPayload {
        var p = TagPayload()
        p.title = title
        p.artist = artist
        p.producer = producer
        p.genre = genre
        p.bpm = workingBpm
        p.key = workingKey
        if hasArtwork, let data = try? Data(contentsOf: artworkURL) {
            let s = ImageInfo.size(of: data)
            p.artwork = Artwork(data: data, mime: "image/jpeg", width: s.0, height: s.1)
        }
        return p
    }

    func matches(search: String) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let key = workingKey
        let hay = [displayTitle, producer, artist, genre, notes, fileName, key?.name ?? "", key?.camelot ?? "",
                   workingBpm.map(BpmMath.format) ?? "", status.label].joined(separator: " ").lowercased()
        return q.split(separator: " ").allSatisfy { hay.contains($0) }
    }
}

/// Where beat files live: Application Support/Beats/<id>/<original name> and Artwork/<id>.jpg.
enum BeatFiles {
    static var root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PrepStation", isDirectory: true)
    }()

    static func folder(id: UUID) -> URL { root.appendingPathComponent("Beats/\(id.uuidString)", isDirectory: true) }
    static func audioURL(id: UUID, fileName: String) -> URL { folder(id: id).appendingPathComponent(fileName) }
    static func artworkURL(id: UUID) -> URL { root.appendingPathComponent("Artwork/\(id.uuidString).jpg") }

    static func prepare() {
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("Beats"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("Artwork"), withIntermediateDirectories: true)
    }

    static func remove(id: UUID) {
        try? FileManager.default.removeItem(at: folder(id: id))
        try? FileManager.default.removeItem(at: artworkURL(id: id))
    }
}
