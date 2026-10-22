import Foundation

/// Synthetic clicks, tones and loops with a known tempo and key (port of the desktop `ReferenceAudio.ts`).
/// Used by the unit tests and the `-demo` library.
enum SyntheticAudio {
    static let majorIntervals = [0, 2, 4, 5, 7, 9, 11]
    static let minorIntervals = [0, 2, 3, 5, 7, 8, 10]

    static func clicks(bpm: Double, seconds: Double, sampleRate: Double = 44100, frequency: Double = 1000) -> [Float] {
        let n = Int(seconds * sampleRate)
        var out = [Float](repeating: 0, count: n)
        let period = 60 / bpm * sampleRate
        let burst = Int(sampleRate * 0.012)
        var beat = 0
        while Double(beat) * period < Double(n) {
            let start = Int((Double(beat) * period).rounded())
            for k in 0..<burst where start + k < n {
                let env = exp(-Double(k) / (sampleRate * 0.0022))
                out[start + k] += Float(sin(2 * .pi * frequency * Double(k) / sampleRate) * env * 0.9)
            }
            beat += 1
        }
        return out
    }

    static func keyedTone(_ key: NamedKey, seconds: Double, sampleRate: Double = 44100, octave: Int = 4) -> [Float] {
        let n = Int(seconds * sampleRate)
        var out = [Double](repeating: 0, count: n)
        let intervals = key.mode == .major ? majorIntervals : minorIntervals
        let tonic = 12 * (octave + 1) + key.pitchClass
        var notes: [(Int, Double)] = intervals.map { (tonic + $0, $0 == 0 ? 0.42 : 0.16) }
        notes.append((tonic - 12, 0.28)); notes.append((tonic + 12, 0.2))
        for (midi, amp) in notes {
            let w = 2 * Double.pi * 440 * pow(2, Double(midi - 69) / 12) / sampleRate
            for i in 0..<n { out[i] += amp * sin(w * Double(i)) }
        }
        return normalize(out.map(Float.init), peak: 0.9)
    }

    /// A small beat: diatonic chords with bass, kick on 1 and 3, snare on 2 and 4, eighth-note hats.
    static func beat(key: NamedKey, bpm: Double, bars: Int = 8, sampleRate: Double = 44100,
                     progression: [Int]? = nil, seed: UInt32 = 7) -> [Float] {
        let scale = key.mode == .major ? majorIntervals : minorIntervals
        let prog = progression ?? (key.mode == .major ? [0, 4, 5, 3] : [0, 5, 6, 0])
        let beatSec = 60 / bpm, barSec = 4 * beatSec
        let n = Int(Double(bars) * barSec * sampleRate) + Int(sampleRate)
        var buf = [Double](repeating: 0, count: n)
        var state = seed
        func rand() -> Double { state = 1664525 &* state &+ 1013904223; return Double(state) / Double(UInt32.max) * 2 - 1 }
        func add(_ startSec: Double, _ dur: Double, _ gen: (Double) -> Double) {
            let s = Int(startSec * sampleRate), len = Int(dur * sampleRate)
            for i in 0..<len where s + i < n { buf[s + i] += gen(Double(i) / sampleRate) }
        }
        let tonic = 48 + key.pitchClass
        func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
        for b in 0..<bars {
            let deg = prog[b % prog.count], t0 = Double(b) * barSec
            for i in [0, 2, 4] {
                let step = deg + i
                let f = hz(tonic + 12 + scale[step % 7] + 12 * (step / 7))
                add(t0, barSec) { t in
                    let p = 2 * Double.pi * f * t
                    return 0.12 * (sin(p) + 0.4 * sin(2 * p) + 0.2 * sin(3 * p)) * min(1, t / 0.01) * exp(-t * 1.2)
                }
            }
            let fb = hz(tonic - 12 + scale[deg])
            for k in [0.0, 2.5] {
                add(t0 + k * beatSec, beatSec * 1.5) { t in
                    0.35 * (sin(2 * .pi * fb * t) + 0.15 * sin(4 * .pi * fb * t)) * min(1, t / 0.005) * exp(-t * 2)
                }
            }
            for k in [0.0, 2.0] {
                var phase = 0.0
                add(t0 + k * beatSec, 0.25) { t in
                    phase += 2 * .pi * (50 + 90 * exp(-t * 30)) / sampleRate
                    return 0.9 * sin(phase) * exp(-t * 12)
                }
            }
            for k in [1.0, 3.0] {
                add(t0 + k * beatSec, 0.18) { t in 0.5 * (rand() * exp(-t * 25) + 0.4 * sin(2 * .pi * 190 * t) * exp(-t * 30)) }
            }
            for h in 0..<8 {
                var last = 0.0
                add(t0 + Double(h) * beatSec / 2, 0.05) { t in
                    let r = rand(); let d = r - last; last = r
                    return 0.18 * d * exp(-t * 80)
                }
            }
        }
        return normalize(buf.map(Float.init), peak: 0.89)
    }

    static func normalize(_ x: [Float], peak: Float) -> [Float] {
        let m = x.reduce(0) { max($0, abs($1)) }
        guard m > 1e-8 else { return x }
        let g = peak / m
        return x.map { $0 * g }
    }

    /// 16-bit PCM WAV bytes (mono).
    static func wavData(_ samples: [Float], sampleRate: Int = 44100) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataSize = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataSize); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataSize)
        var pcm = [Int16](repeating: 0, count: samples.count)
        for i in 0..<samples.count { pcm[i] = Int16(max(-1, min(1, samples[i])) * 32767) }
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }
}
