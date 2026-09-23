import SwiftUI

// MARK: - Morning Stage palette
//
// Speaking Coach is the daytime sibling of a night app: warm paper light that
// *gathers* as the user commits, instead of a sky that deepens. One accent —
// the icon's coral — and warm ink instead of black, so nothing reads clinical.
// Every surface is a paper tone rather than white: white has no temperature,
// and glass over flat white is invisible.

extension Color {
    /// Hex convenience, e.g. `Color(hex: 0xFF5A5F)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Palette {
    // Ground. Five stops with a real hue journey — a near-white crown warming
    // through cream to apricot, where the sunrise sits. Two-stop gradients are
    // what make a light background look like a default rather than a place.
    // The ground leans yellow and stays low-chroma on purpose: coral is the
    // one accent, and a salmon ground would swallow every coral fill on it.
    static let skyCrown = Color(hex: 0xFFFBF7)
    static let skyHigh = Color(hex: 0xFDF7F1)
    static let skyMid = Color(hex: 0xFAF0E7)
    static let skyLow = Color(hex: 0xF6E7DA)
    static let skyBase = Color(hex: 0xF1DCCB)
    static let paper = skyCrown

    // Brand. `coral` is the icon's own color. On paper it is a *fill* color —
    // glyphs and text that need contrast use `coralDeep`.
    static let coral = Color(hex: 0xFF5A5F)
    static let coralDeep = Color(hex: 0xD2414A)
    static let peach = Color(hex: 0xFFB199)
    static let sun = Color(hex: 0xFFE6CF)
    /// The sunrise's outer halo — apricot, not peach, so it warms the ground
    /// without reddening it.
    static let glow = Color(hex: 0xF5D3B8)

    // Ink — warm near-black, never #000.
    static let ink = Color(hex: 0x231A1B)
    static let dim = Color(hex: 0x6B5A5B)
    static let muted = Color(hex: 0x98888A)
    static let faint = Color(hex: 0x231A1B, opacity: 0.22)

    // Meaning. Used sparingly: sage marks something the user did well,
    // danger marks a real failure (never guidance).
    static let sage = Color(hex: 0x4F8A63)
    static let danger = Color(hex: 0xC8323C)

    // Lines and glass. On a light ground the fallback glass needs a *white*
    // wash so it lifts off the paper instead of sinking into it.
    static let hairline = Color(hex: 0x231A1B, opacity: 0.07)
    static let border = Color(hex: 0x231A1B, opacity: 0.10)
    static let glassFill = Color.white.opacity(0.52)
    static let glassCoral = Color(hex: 0xFF5A5F, opacity: 0.14)
}

// MARK: - Spacing (8pt grid) and corners

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 48
}

enum Corner {
    static let sm: CGFloat = 14
    static let md: CGFloat = 18
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
}

// MARK: - Motion

enum Motion {
    /// Steps fade; they do not slide. Out fast, in slower, never overlapping.
    static let fadeOut: Double = 0.16
    static let fadeIn: Double = 0.32
    /// How long a new step's primary action stays inert, so a tap meant for
    /// the previous screen can't answer a question nobody has read yet.
    static let settle: Duration = .milliseconds(900)
    static let press = Animation.spring(response: 0.3, dampingFraction: 0.58)
}
