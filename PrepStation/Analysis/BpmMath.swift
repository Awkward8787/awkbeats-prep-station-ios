import Foundation

enum BpmMath {
    static func round2(_ bpm: Double) -> Double { (bpm * 100).rounded() / 100 }

    /// DAW tempos are usually whole numbers; snap 139.98 to 140 but keep 102.75.
    static func tidy(_ bpm: Double) -> Double {
        let whole = bpm.rounded()
        return abs(bpm - whole) <= 0.03 ? whole : round2(bpm)
    }

    static func inRange(_ bpm: Double) -> Bool { bpm.isFinite && bpm >= 40 && bpm <= 300 }

    /// Working tempo: a custom value wins, else detected × scale (½×, 1×, 2×).
    static func working(detected: Double?, scale: Double, override: Double?) -> Double? {
        if let o = override, o.isFinite { return round2(o) }
        guard let d = detected, d.isFinite else { return nil }
        return round2(d * scale)
    }

    /// "140" or "102.75". Used for display and the ID3 TBPM frame.
    static func format(_ bpm: Double) -> String {
        let r = round2(bpm)
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.2f", r)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }
}
