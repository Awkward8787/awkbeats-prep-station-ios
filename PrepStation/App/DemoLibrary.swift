import UIKit
import SwiftData

/// `-demo` launch flag: an in-memory library of synthetic beats (real audio, real detection) for screenshots.
@MainActor
enum DemoLibrary {
    struct Item { let title: String; let artist: String; let genre: String; let key: String; let bpm: Double; let status: BeatStatus; let art: Int? }

    static let items: [Item] = [
        Item(title: "Gold Hour", artist: "Kaia Moon", genre: "R&B", key: "A minor", bpm: 92, status: .ready, art: 0),
        Item(title: "Night Drive", artist: "", genre: "Trap", key: "F# minor", bpm: 140, status: .inProgress, art: 1),
        Item(title: "Alley Light", artist: "Dre Vance", genre: "Boom bap", key: "D minor", bpm: 88, status: .leased, art: 2),
        Item(title: "Glassroom", artist: "", genre: "Drill", key: "C# minor", bpm: 142, status: .idea, art: nil),
        Item(title: "Velvet Rope", artist: "Nia Sol", genre: "R&B", key: "E major", bpm: 98, status: .sold, art: 3),
        Item(title: "Southside Rain", artist: "", genre: "Trap", key: "G minor", bpm: 145, status: .ready, art: nil),
    ]

    static func seed(_ context: ModelContext) {
        if LaunchFlags.demoEmpty { return }
        BeatFiles.prepare()
        for (i, item) in items.enumerated() {
            let id = UUID()
            let key = Camelot.parse(item.key)!
            let samples = SyntheticAudio.beat(key: key, bpm: item.bpm, bars: 4, sampleRate: 22050, seed: UInt32(11 + i))
            let name = item.title.replacingOccurrences(of: " ", with: "_") + ".wav"
            try? FileManager.default.createDirectory(at: BeatFiles.folder(id: id), withIntermediateDirectories: true)
            let data = SyntheticAudio.wavData(samples, sampleRate: 22050)
            try? data.write(to: BeatFiles.audioURL(id: id, fileName: name))
            let beat = Beat(id: id, fileName: name, format: .wav, fileSize: data.count, title: item.title, producer: "Awkward J")
            beat.artist = item.artist
            beat.genre = item.genre
            beat.status = item.status
            beat.importedAt = Date().addingTimeInterval(Double(-i) * 3600)
            if let a = item.art, let jpeg = artwork(a) {
                try? jpeg.write(to: BeatFiles.artworkURL(id: id))
                beat.hasArtwork = true
            }
            if item.status == .leased || item.status == .sold { beat.tagsDirty = false; beat.tagsSavedAt = Date() }
            context.insert(beat)
            BeatImporter.analyze(beat, context: context)
        }
        try? context.save()
    }

    /// Simple abstract cover art in the brand palette (placeholder art for the demo only).
    static func artwork(_ variant: Int) -> Data? {
        let size = CGSize(width: 600, height: 600)
        let palettes: [(UInt32, UInt32)] = [(0x3A2260, 0xE4B15A), (0x1B1029, 0x8EE0B8), (0x2F1D4A, 0xF4A6C8), (0x24163A, 0x9EB6F0)]
        let (bg, fg) = palettes[variant % palettes.count]
        func ui(_ hex: UInt32, _ a: CGFloat = 1) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
        }
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            ui(bg).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            let c = ctx.cgContext
            switch variant % 4 {
            case 0:
                ui(fg).setFill(); c.fillEllipse(in: CGRect(x: 150, y: 150, width: 300, height: 300))
                ui(bg).setFill(); c.fill(CGRect(x: 0, y: 330, width: 600, height: 270))
                ui(fg, 0.5).setFill(); for i in 0..<5 { c.fill(CGRect(x: 0, y: 360 + i * 44, width: 600, height: 10)) }
            case 1:
                ui(fg, 0.85).setStroke(); c.setLineWidth(6)
                for i in 0..<9 { c.strokeEllipse(in: CGRect(x: 300 - i * 32, y: 300 - i * 32, width: i * 64, height: i * 64)) }
            case 2:
                ui(fg).setFill()
                for i in 0..<12 { let h = CGFloat(60 + (i * 53) % 300); c.fill(CGRect(x: 40 + CGFloat(i) * 45, y: 520 - h, width: 26, height: h)) }
            default:
                ui(fg, 0.9).setFill()
                c.move(to: CGPoint(x: 300, y: 90)); c.addLine(to: CGPoint(x: 520, y: 500)); c.addLine(to: CGPoint(x: 80, y: 500)); c.fillPath()
                ui(bg).setFill(); c.fillEllipse(in: CGRect(x: 230, y: 300, width: 140, height: 140))
            }
        }
        return img.jpegData(compressionQuality: 0.9)
    }
}
