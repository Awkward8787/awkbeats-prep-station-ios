import Foundation
import SwiftData
import UniformTypeIdentifiers

enum ImportError: LocalizedError {
    case unsupported(String)
    var errorDescription: String? {
        switch self {
        case .unsupported(let name): return "\(name) isn't a supported audio file. Use MP3, WAV, FLAC, M4A or AIFF."
        }
    }
}

/// Copies picked or shared files into the app, reads existing tags, then runs detection in the background.
@MainActor
enum BeatImporter {
    static var supportedTypes: [UTType] {
        var t: [UTType] = [.mp3, .wav, .aiff, .mpeg4Audio]
        if let flac = UTType("org.xiph.flac") { t.append(flac) }
        if let flac = UTType(filenameExtension: "flac"), !t.contains(flac) { t.append(flac) }
        t.append(.audio)
        return t
    }

    /// Imports one file. `url` may be security-scoped (Files picker) or an Inbox copy (share sheet).
    @discardableResult
    static func importFile(_ url: URL, into context: ModelContext, defaultProducer: String) async throws -> Beat {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        guard let format = AudioFormat(fileExtension: url.pathExtension) else { throw ImportError.unsupported(name) }
        BeatFiles.prepare()
        let id = UUID()
        try FileManager.default.createDirectory(at: BeatFiles.folder(id: id), withIntermediateDirectories: true)
        let dest = BeatFiles.audioURL(id: id, fileName: name)
        try FileManager.default.copyItem(at: url, to: dest)
        if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0

        let tags = await TagReader.read(url: dest, format: format)
        let title = tags.title.isEmpty ? (name as NSString).deletingPathExtension : tags.title
        let beat = Beat(id: id, fileName: name, format: format, fileSize: size, title: title,
                        producer: tags.producer.isEmpty ? defaultProducer : tags.producer)
        beat.artist = tags.artist
        beat.genre = tags.genre
        // Values the producer already tagged win over detection; detection still runs and is shown.
        if let bpm = tags.bpm, BpmMath.inRange(bpm) { beat.bpmOverride = bpm }
        if let key = tags.key { beat.keyOverride = key.name }
        if let art = tags.artwork, let jpeg = ArtworkProcessor.normalized(art.data) {
            try? jpeg.write(to: BeatFiles.artworkURL(id: id))
            beat.hasArtwork = true
        }
        context.insert(beat)
        try? context.save()
        analyze(beat, context: context)
        return beat
    }

    static func analyze(_ beat: Beat, context: ModelContext) {
        beat.analysisState = "pending"
        let url = beat.fileURL
        let id = beat.persistentModelID
        Task.detached(priority: .userInitiated) {
            let result = try? TrackAnalyzer.analyze(url: url)
            await MainActor.run {
                guard let b = context.model(for: id) as? Beat else { return }
                if let r = result {
                    b.bpmDetected = r.bpm
                    b.bpmConfidence = r.bpmConfidence
                    b.keyDetected = r.key?.name
                    b.keyConfidence = r.keyConfidence
                    b.durationSec = r.durationSec
                    b.sampleRate = r.sampleRate
                    b.peaks = r.peaks
                    b.analysisState = "done"
                } else {
                    b.analysisState = "failed"
                }
                try? context.save()
            }
        }
    }
}
