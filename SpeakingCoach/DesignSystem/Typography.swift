import SwiftUI
import UIKit

// MARK: - Type
//
// **DM Sans** throughout (SIL OFL — see CREDITS.md), bundled as its variable
// font and driven on both axes, exactly as in SleepBlock. Four roles:
//
// - Hero (weight 600): the one big thing on a screen — the wordmark, a name,
//   a paywall headline, a pattern.
// - Title (500): questions and prominent values.
// - Body (400): copy.
// - Label (500): buttons, rows, tracked small caps.
//
// The optical-size axis matters: the font defaults `opsz` to 9, so without
// mapping it to the point size every hero renders in the loose text cut.

enum Typeface {
    static func hero(_ size: CGFloat) -> Font { dmSans(size, weight: 600) }
    static func title(_ size: CGFloat) -> Font { dmSans(size, weight: 500) }
    static func body(_ size: CGFloat) -> Font { dmSans(size, weight: 400) }
    static func label(_ size: CGFloat) -> Font { dmSans(size, weight: 500) }
    /// The real italic cut, never the roman sheared by the system.
    static func bodyItalic(_ size: CGFloat) -> Font { dmSans(size, weight: 400, italic: true) }

    // MARK: DM Sans instancing

    /// PostScript names of the bundled variable fonts. The family name carries
    /// the default optical size, so this is *not* "DMSans-Regular" — and a
    /// wrong name fails silently into San Francisco.
    private static let romanName = "DMSans-9ptRegular"
    private static let italicName = "DMSans-9ptItalic"
    private static let opszAxis = 0x6F70_737A // 'opsz'
    private static let wghtAxis = 0x7767_6874 // 'wght'

    static var isAvailable: Bool { UIFont(name: romanName, size: 12) != nil }

    static func uiFont(size: CGFloat, weight: CGFloat, italic: Bool = false) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: italic ? italicName : romanName,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [
                opszAxis: min(max(size, 9), 40),
                wghtAxis: weight,
            ],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func dmSans(_ size: CGFloat, weight: CGFloat, italic: Bool = false) -> Font {
        Font(uiFont(size: size, weight: weight, italic: italic))
    }
}

/// Tracked small caps — the app's kicker grammar (SleepBlock's `sectionLabel`).
struct Kicker: View {
    let text: String
    var color: Color = Palette.dim

    var body: some View {
        Text(text.uppercased())
            .font(Typeface.label(12))
            .tracking(1.6)
            .foregroundStyle(color)
    }
}
