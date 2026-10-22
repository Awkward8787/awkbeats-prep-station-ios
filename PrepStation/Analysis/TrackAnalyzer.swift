import Foundation
import AVFoundation

struct AnalysisResult {
    var bpm: Double?
    var bpmConfidence: Double?
    var key: NamedKey?
    var keyConfidence: Double?
    var durationSec: Double
    var sampleRate: Double
    var peaks: [Float]
}

enum AudioDecodeError: LocalizedError {
    case unreadable
    var errorDescription: String? { "This file couldn't be read as audio." }
}

/// Decodes the first 90 seconds to mono float and runs key and tempo detection (same cap as the desktop).
enum TrackAnalyzer {
    static let maxSeconds = 90.0

    static func analyze(url: URL) throws -> AnalysisResult {
        let (samples, sr, duration) = try decodeMono(url: url, maxSeconds: maxSeconds)
        var r = analyze(samples: samples, sampleRate: sr)
        r.durationSec = duration
        return r
    }

    static func analyze(samples: [Float], sampleRate: Double) -> AnalysisResult {
        var result = AnalysisResult(durationSec: Double(samples.count) / sampleRate, sampleRate: sampleRate,
                                    peaks: peaks(samples, buckets: 120))
        if let tempo = try? BpmDetector.detect(samples, sampleRate: sampleRate) {
            result.bpm = tempo.bpm
            result.bpmConfidence = tempo.confidence
        }
        if samples.count >= 2048 {
            let key = KeyDetector.detect(samples, sampleRate: sampleRate)
            if key.confidence > 0 {
                result.key = key.key
                result.keyConfidence = key.confidence
            }
        }
        return result
    }

    /// Returns mono samples (channel average), sample rate, and the full file duration in seconds.
    static func decodeMono(url: URL, maxSeconds: Double) throws -> ([Float], Double, Double) {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw AudioDecodeError.unreadable }
        let format = file.processingFormat
        let sr = format.sampleRate
        let total = file.length
        let duration = sr > 0 ? Double(total) / sr : 0
        let wanted = AVAudioFrameCount(min(Double(total), maxSeconds * sr))
        guard wanted > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: wanted) else {
            throw AudioDecodeError.unreadable
        }
        do { try file.read(into: buffer, frameCount: wanted) } catch { throw AudioDecodeError.unreadable }
        guard let channels = buffer.floatChannelData else { throw AudioDecodeError.unreadable }
        let n = Int(buffer.frameLength), c = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: n)
        for ch in 0..<c {
            let p = channels[ch]
            for i in 0..<n { mono[i] += p[i] }
        }
        if c > 1 { let g = 1 / Float(c); for i in 0..<n { mono[i] *= g } }
        return (mono, sr, duration)
    }

    static func peaks(_ samples: [Float], buckets: Int) -> [Float] {
        guard !samples.isEmpty, buckets > 0 else { return [] }
        let size = max(1, samples.count / buckets)
        var out: [Float] = []
        var start = 0
        while start < samples.count && out.count < buckets {
            let end = min(samples.count, start + size)
            var peak: Float = 0
            for j in start..<end { peak = max(peak, abs(samples[j])) }
            out.append(peak)
            start = end
        }
        if let m = out.max(), m > 0 { out = out.map { $0 / m } }
        return out
    }
}
