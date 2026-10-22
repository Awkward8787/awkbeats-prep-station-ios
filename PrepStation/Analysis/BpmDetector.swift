import Foundation

struct BpmEstimate {
    /// Tempo of the beat, snapped to a whole number when within 0.03, else 0.01 BPM.
    let bpm: Double
    /// 0–1: share of onset energy that lands on the detected eighth-note grid.
    let confidence: Double
    /// Tempo from the coarse search, before the grid fit.
    let coarse: Double
}

/// Offline tempo detection.
///
/// Keeps the desktop idea (time onsets precisely, then fit a straight line through them so a steady grid
/// resolves to 0.01 BPM) but finds the beat period from a log spectral-flux envelope instead of raw energy
/// peaks. On beats where the kick only lands on 1 and 3 the desktop picked those kicks and reported half
/// tempo; the flux envelope also hears snares and hats.
///
/// 1. Onset strength: half-wave-rectified log-magnitude spectral flux (1024-sample frames, hop 256), minus a 0.5 s local mean.
/// 2. Coarse tempo: autocorrelation scored at the beat, the half-bar, the bar and the eighth note,
///    with a gentle log-normal preference around 115 BPM, searched from 60 to 200 BPM in 0.1 steps.
/// 3. Exact tempo: peak-picked onsets are assigned to the eighth-note grid and fit with weighted least squares.
enum BpmDetector {
    static let minBpm = 60.0, maxBpm = 200.0

    enum DetectError: Error { case tooShort }

    static func detect(_ samples: [Float], sampleRate: Double) throws -> BpmEstimate {
        guard sampleRate >= 8000, Double(samples.count) >= sampleRate * 3 else { throw DetectError.tooShort }
        let (env, frameRate) = onsetEnvelope(samples, sampleRate: sampleRate)
        let coarse = coarseTempo(env, frameRate: frameRate)
        let (bpm, conf) = refine(env, frameRate: frameRate, coarse: coarse)
        return BpmEstimate(bpm: BpmMath.tidy(bpm), confidence: conf, coarse: coarse)
    }

    static func onsetEnvelope(_ x: [Float], sampleRate: Double, n: Int = 1024, hop: Int = 256) -> ([Double], Double) {
        let frames = 1 + (x.count - n) / hop
        guard frames > 2 else { return ([], sampleRate / Double(hop)) }
        let fft = RealFFT(size: n)
        let window = RealFFT.hann(n)
        var frame = [Float](repeating: 0, count: n)
        var mag = [Float]()
        var prev = [Float](repeating: 0, count: n / 2 + 1)
        var cur = prev
        var flux = [Double](repeating: 0, count: frames)
        x.withUnsafeBufferPointer { xp in
            for f in 0..<frames {
                let start = f * hop
                for i in 0..<n { frame[i] = xp[start + i] * window[i] }
                frame.withUnsafeBufferPointer { fft.magnitudes($0.baseAddress!, into: &mag) }
                for k in 0..<mag.count { cur[k] = log1pf(100 * mag[k]) }
                if f > 0 {
                    var s: Float = 0
                    for k in 0..<cur.count { let d = cur[k] - prev[k]; if d > 0 { s += d } }
                    flux[f] = Double(s)
                }
                swap(&prev, &cur)
            }
        }
        let frameRate = sampleRate / Double(hop)
        // Subtract a centred 0.5 s moving average, keep the positive part.
        let k = Int(0.5 * frameRate) | 1
        let half = k / 2
        var prefix = [Double](repeating: 0, count: frames + 1)
        for i in 0..<frames { prefix[i + 1] = prefix[i] + flux[i] }
        var out = [Double](repeating: 0, count: frames)
        for i in 0..<frames {
            let lo = max(0, i - half), hi = min(frames, i + half + 1)
            let mean = (prefix[hi] - prefix[lo]) / Double(k)   // zero-padded edges, like numpy 'same'
            out[i] = max(0, flux[i] - mean)
        }
        return (out, frameRate)
    }

    static func coarseTempo(_ env: [Double], frameRate: Double) -> Double {
        let count = env.count
        guard count > 8 else { return 120 }
        let mean = env.reduce(0, +) / Double(count)
        let o = env.map { $0 - mean }
        let maxLag = min(count - 2, Int((60 * frameRate / minBpm) * 4) + 2)
        var ac = [Double](repeating: 0, count: maxLag + 2)
        o.withUnsafeBufferPointer { p in
            for lag in 0...maxLag {
                var s = 0.0
                let limit = count - lag
                for i in 0..<limit { s += p[i] * p[i + lag] }
                ac[lag] = s / Double(limit)
            }
        }
        func acf(_ lag: Double) -> Double {
            let i = Int(lag), f = lag - Double(i)
            guard i >= 0, i + 1 < ac.count else { return 0 }
            return ac[i] * (1 - f) + ac[i + 1] * f
        }
        var bestBpm = 120.0, best = -Double.infinity
        var b = minBpm
        while b <= maxBpm + 1e-9 {
            let lag = 60 * frameRate / b
            let s = acf(lag) + 0.5 * acf(2 * lag) + 0.25 * acf(4 * lag) + 0.5 * acf(lag / 2)
            let octaves = log2(b / 115) / 0.75
            let score = s * exp(-0.5 * octaves * octaves)
            if score > best { best = score; bestBpm = b }
            b += 0.1
        }
        return bestBpm
    }

    static func refine(_ env: [Double], frameRate: Double, coarse: Double) -> (Double, Double) {
        guard env.count > 3 else { return (coarse, 0) }
        let threshold = percentile(env, 0.90) * 0.5
        var times: [Double] = [], weights: [Double] = []
        for i in 1..<(env.count - 1) where env[i] > threshold && env[i] >= env[i - 1] && env[i] > env[i + 1] {
            let y0 = env[i - 1], y1 = env[i], y2 = env[i + 1]
            let denom = y0 - 2 * y1 + y2
            let d = denom != 0 ? 0.5 * (y0 - y2) / denom : 0
            times.append((Double(i) + d) / frameRate)
            weights.append(y1)
        }
        guard times.count >= 8 else { return (coarse, 0) }
        var period = 60 / coarse / 2   // eighth note
        var confidence = 0.0
        let totalWeight = weights.reduce(0, +)
        for _ in 0..<3 {
            var cr = 0.0, ci = 0.0
            for (t, w) in zip(times, weights) {
                let a = 2 * Double.pi * t / period
                cr += w * cos(a); ci += w * sin(a)
            }
            let phase = atan2(ci, cr) * period / (2 * Double.pi)
            var sw = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, used = 0
            for (t, w) in zip(times, weights) {
                let idx = ((t - phase) / period).rounded()
                let residual = t - phase - idx * period
                guard abs(residual) < period * 0.12 else { continue }
                used += 1
                sw += w; sx += w * idx; sy += w * t; sxx += w * idx * idx; sxy += w * idx * t
            }
            let denom = sw * sxx - sx * sx
            guard used >= 8, abs(denom) > 1e-12 else { return (coarse, confidence) }
            period = (sw * sxy - sx * sy) / denom
            confidence = totalWeight > 0 ? sw / totalWeight : 0
        }
        let bpm = 60 / (2 * period)
        guard bpm.isFinite, bpm > 30, bpm < 400 else { return (coarse, 0) }
        return (bpm, confidence)
    }

    /// Linear-interpolated percentile (numpy default).
    static func percentile(_ values: [Double], _ q: Double) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        let pos = q * Double(s.count - 1)
        let lo = Int(pos.rounded(.down)), hi = min(s.count - 1, lo + 1)
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }
}
