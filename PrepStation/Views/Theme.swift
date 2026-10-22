import SwiftUI

/// AwkBeats plum + gold tokens (same as the Prep Station desktop app and InKey; every text pair checked for WCAG AA).
/// Rules: gold text only on plum-950...plum-active; text on gold fills uses `goldInk`;
/// the logo plum (#701888) is decorative only and is never used for text, icons or borders.
enum Theme {
    // Surfaces
    static let plum950 = Color(hex: 0x140B1F)   // app background
    static let plum900 = Color(hex: 0x1B1029)   // sheets / grouped background
    static let plum850 = Color(hex: 0x24163A)   // cards
    static let plum800 = Color(hex: 0x2F1D4A)   // secondary buttons, pills
    static let plumActive = Color(hex: 0x3A2260) // selected (always paired with a gold edge)
    static let line = Color(hex: 0x3A2A52)       // decorative dividers
    static let lineControl = Color(hex: 0x7D68A0) // control boundaries (3:1)
    // Text
    static let text = Color(hex: 0xF7F2FB)
    static let textDim = Color(hex: 0xCDBFE0)
    static let textFaint = Color(hex: 0xA896C2)
    // Signature accent
    static let gold = Color(hex: 0xE4B15A)
    static let goldText = Color(hex: 0xF3D7A4)
    static let goldInk = Color(hex: 0x1F1405)
    // Status
    static let mint = Color(hex: 0x8EE0B8)
    static let danger = Color(hex: 0xF09A86)
    static let leased = Color(hex: 0x9EB6F0)
    static let sold = Color(hex: 0xF4A6C8)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Primary action: gold fill with dark ink (never white on gold).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.goldInk)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.gold.opacity(configuration.isPressed ? 0.85 : 1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary action: plum fill, light text, visible 3:1 edge.
struct SecondaryButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 50
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(configuration.isPressed ? Theme.plumActive : Theme.plum800,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.lineControl, lineWidth: 1))
    }
}

/// Small, quiet brand line.
struct PoweredByAwkBeats: View {
    var body: some View {
        HStack(spacing: 6) {
            Image("AwkBeatsLogo")
                .resizable().scaledToFit()
                .frame(height: 12)
                .accessibilityHidden(true)
            Text("Powered by AwkBeats")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textFaint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Powered by AwkBeats")
    }
}

extension BeatStatus {
    /// Status colors always sit next to the word (never color alone). All pass AA on plum-800.
    var color: Color {
        switch self {
        case .idea: return Theme.textFaint
        case .inProgress: return Theme.gold
        case .ready: return Theme.mint
        case .leased: return Theme.leased
        case .sold: return Theme.sold
        }
    }
}

/// Grouped card: plum-850 fill with a visible edge (fill alone is 1.09:1 against plum-900).
struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textFaint)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.plum850, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Camelot code in gold-text with a gold border (9.8:1 on plum-950).
struct CamelotBadge: View {
    let code: String
    var large = false
    var body: some View {
        Text(code)
            .font((large ? Font.title3 : .caption).weight(.semibold).monospacedDigit())
            .foregroundStyle(Theme.goldText)
            .padding(.horizontal, large ? 10 : 6)
            .padding(.vertical, large ? 4 : 2)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.gold, lineWidth: 1))
            .accessibilityLabel("Camelot \(code)")
    }
}

struct StatusPill: View {
    let status: BeatStatus
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status.color).frame(width: 6, height: 6)
            Text(status.label).font(.caption2.weight(.medium)).foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Theme.plum800, in: Capsule())
    }
}
