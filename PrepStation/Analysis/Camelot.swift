import Foundation

enum KeyMode: String, Codable, CaseIterable {
    case major, minor
}

/// A musical key with its Camelot code. Pitch class 0 is C. Ported from the desktop `Camelot.ts`.
struct NamedKey: Equatable, Hashable {
    let pitchClass: Int
    let mode: KeyMode

    var root: String { Camelot.roots[pitchClass] }
    /// Standard notation, for example "F# minor".
    var name: String { "\(root) \(mode.rawValue)" }
    /// Camelot code, for example "11A".
    var camelot: String { mode == .major ? Camelot.majorCodes[pitchClass] : Camelot.minorCodes[pitchClass] }
    /// Short form used in ID3 TKEY (max three characters), for example "F#m".
    var shortName: String { root + (mode == .minor ? "m" : "") }
    /// Root, third and fifth pitch classes.
    var triad: [Int] { [pitchClass, (pitchClass + (mode == .minor ? 3 : 4)) % 12, (pitchClass + 7) % 12] }
}

enum Camelot {
    static let roots = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let majorCodes = ["8B", "3B", "10B", "5B", "12B", "7B", "2B", "9B", "4B", "11B", "6B", "1B"]
    static let minorCodes = ["5A", "12A", "7A", "2A", "9A", "4A", "11A", "6A", "1A", "8A", "3A", "10A"]
    private static let flatToSharp = ["DB": "C#", "EB": "D#", "GB": "F#", "AB": "G#", "BB": "A#"]

    static func key(_ pitchClass: Int, _ mode: KeyMode) -> NamedKey {
        NamedKey(pitchClass: ((pitchClass % 12) + 12) % 12, mode: mode)
    }

    /// Every key in Camelot order (1A, 1B, 2A, ...), for pickers.
    static var allKeys: [NamedKey] {
        (1...12).flatMap { n -> [NamedKey] in
            [parse("\(n)A")!, parse("\(n)B")!]
        }
    }

    /// Accepts "8A", "A minor", "Am", "Bbm", "F# maj", "C".
    static func parse(_ value: String?) -> NamedKey? {
        guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let chars = Array(raw.replacingOccurrences(of: " ", with: ""))
        guard !chars.isEmpty else { return nil }
        // Camelot code: 1-2 digits then A or B.
        if chars[0].isNumber {
            let digits = String(chars.prefix { $0.isNumber })
            let rest = String(chars.dropFirst(digits.count)).uppercased()
            guard let num = Int(digits), (1...12).contains(num), rest == "A" || rest == "B" else { return nil }
            let code = "\(num)\(rest)"
            if rest == "B", let pc = majorCodes.firstIndex(of: code) { return key(pc, .major) }
            if rest == "A", let pc = minorCodes.firstIndex(of: code) { return key(pc, .minor) }
            return nil
        }
        let letter = String(chars[0]).uppercased()
        guard "ABCDEFG".contains(letter) else { return nil }
        var index = 1
        var root = letter
        if index < chars.count, chars[index] == "#" || chars[index] == "♯" {
            root += "#"; index += 1
        } else if index < chars.count, chars[index] == "b" || chars[index] == "♭" {
            index += 1
            if let sharp = flatToSharp[root + "B"] { root = sharp }
            else if root == "C" { root = "B" }
            else if root == "F" { root = "E" }
            else { return nil }
        }
        return finish(root, String(chars[index...]))
    }

    private static func finish(_ root: String, _ modeToken: String) -> NamedKey? {
        guard let pc = roots.firstIndex(of: root) else { return nil }
        switch modeToken.lowercased() {
        case "", "maj", "major": return key(pc, .major)
        case "m", "min", "minor": return key(pc, .minor)
        default: return nil
        }
    }
}
