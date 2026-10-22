import Foundation

/// Notes for the key reference sounds. Pure, so it is unit tested.
enum KeyReference {
    struct Note: Equatable { let midi: Int; let start: Double; let duration: Double; let amplitude: Double }

    enum Kind: String { case chord, drone }

    static func frequency(midi: Int, a4: Double = 440) -> Double { a4 * pow(2, Double(midi - 69) / 12) }

    /// Tonic triad voiced around middle C with the root doubled an octave below.
    /// Chord: a 0.1 s strum that rings for 2.6 s. Drone: root, fifth and low root, sustained (duration = .infinity).
    static func notes(_ kind: Kind, key: NamedKey) -> [Note] {
        // Root in octave 3 (C3 = 48) keeps every key between ~130 and ~400 Hz.
        let root = 48 + key.pitchClass
        switch kind {
        case .chord:
            let third = root + (key.mode == .minor ? 3 : 4)
            return [
                Note(midi: root - 12, start: 0, duration: 2.6, amplitude: 0.20),
                Note(midi: root, start: 0.0, duration: 2.6, amplitude: 0.17),
                Note(midi: third, start: 0.05, duration: 2.55, amplitude: 0.15),
                Note(midi: root + 7, start: 0.10, duration: 2.5, amplitude: 0.15),
            ]
        case .drone:
            return [
                Note(midi: root - 12, start: 0, duration: .infinity, amplitude: 0.20),
                Note(midi: root, start: 0, duration: .infinity, amplitude: 0.16),
                Note(midi: root + 7, start: 0, duration: .infinity, amplitude: 0.11),
            ]
        }
    }

    /// Attack / release envelope; drones swell in over 0.4 s.
    static func gain(at t: Double, duration: Double) -> Double {
        if t < 0 { return 0 }
        if duration.isInfinite { return min(1, t / 0.4) }
        let attack = min(1, t / 0.012)
        let decay = exp(-t * 0.9)
        let release = min(1, max(0, (duration - t) / 0.25))
        return attack * decay * release
    }
}
