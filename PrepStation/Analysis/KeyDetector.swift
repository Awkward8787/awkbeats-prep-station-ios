import Foundation

struct KeyEstimate {
    let key: NamedKey
    /// 0–1 gap between the winning key and the runner-up (desktop formula).
    let confidence: Double
    let correlation: Double
    let chroma: [Double]

    /// Below this the runner-up is close enough that the producer should check by ear (desktop `KeyConfidence`).
    static let reviewAt = 0.45
    var needsReview: Bool { confidence < Self.reviewAt }
}

/// Offline musical-key detection, ported 1:1 from the desktop `KeyDetector.ts`.
/// A long-window FFT collects pitch-class energy from spectral peaks. Each of the 24 keys is scored
/// by Pearson correlation against the Krumhansl–Schmuckler profile plus tonic salience.
enum KeyDetector {
    /// Krumhansl–Schmuckler probe-tone weights (Cognitive Foundations of Musical Pitch, 1990). Index 0 = tonic.
    static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.6, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    static func detect(_ samples: [Float], sampleRate: Double) -> KeyEstimate {
        let chroma = self.chroma(samples, sampleRate: sampleRate)
        let total = chroma.reduce(0, +)
        if total < 1e-8 {
            return KeyEstimate(key: Camelot.key(0, .major), confidence: 0, correlation: 0, chroma: chroma)
        }
        let maxChroma = chroma.max() ?? 0
        var best = -Double.infinity, second = -Double.infinity
        var bestKey = Camelot.key(0, .major), bestCorr = 0.0
        for mode in [KeyMode.major, .minor] {
            let profile = mode == .major ? majorProfile : minorProfile
            for pc in 0..<12 {
                let corr = pearson(chroma, rotate(profile, pc))
                let salience = maxChroma > 0 ? chroma[pc] / maxChroma : 0
                let score = 0.82 * corr + 0.18 * salience
                if score > best {
                    second = best; best = score; bestKey = Camelot.key(pc, mode); bestCorr = corr
                } else if score > second {
                    second = score
                }
            }
        }
        let gap = best - (second.isFinite ? second : 0)
        return KeyEstimate(key: bestKey, confidence: max(0, min(1, gap / 0.12)), correlation: bestCorr, chroma: chroma)
    }

    static func chroma(_ samples: [Float], sampleRate: Double) -> [Double] {
        let fftSize = 16384, hop = 8192
        var chroma = [Double](repeating: 0, count: 12)
        let fft = RealFFT(size: fftSize)
        let window = RealFFT.hann(fftSize)
        var frame = [Float](repeating: 0, count: fftSize)
        var mag = [Float]()
        func accumulate(_ start: Int) {
            for i in 0..<fftSize {
                let j = start + i
                frame[i] = (j < samples.count ? samples[j] : 0) * window[i]
            }
            frame.withUnsafeBufferPointer { fft.magnitudes($0.baseAddress!, into: &mag) }
            let binHz = sampleRate / Double(fftSize)
            for k in 1..<(mag.count - 1) {
                guard mag[k] >= mag[k - 1], mag[k] > mag[k + 1] else { continue }
                let freq = Double(k) * binHz
                if freq < 60 || freq > 4200 { continue }
                let midi = 69 + 12 * log2(freq / 440)
                let nearest = midi.rounded()
                let distance = abs(midi - nearest)
                if distance > 0.45 { continue }
                let pc = ((Int(nearest) % 12) + 12) % 12
                chroma[pc] += Double(mag[k]) * (1 - distance / 0.45)
            }
        }
        if samples.count < fftSize {
            accumulate(0)
        } else {
            var start = 0
            while start + fftSize <= samples.count { accumulate(start); start += hop }
        }
        return chroma
    }

    static func rotate(_ profile: [Double], _ shift: Int) -> [Double] {
        var out = [Double](repeating: 0, count: 12)
        for i in 0..<12 { out[(i + shift) % 12] = profile[i] }
        return out
    }

    static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count)
        let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var num = 0.0, da2 = 0.0, db2 = 0.0
        for i in 0..<a.count {
            let da = a[i] - ma, db = b[i] - mb
            num += da * db; da2 += da * da; db2 += db * db
        }
        if da2 <= 1e-12 || db2 <= 1e-12 { return 0 }
        return num / (da2 * db2).squareRoot()
    }
}
