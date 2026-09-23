import SwiftUI
import UIKit

/// The ground every pre-app screen stands on: warm paper sky, a sunrise
/// glowing up from below the bottom edge, and slow sound-ripples rising off
/// it — the app's subject (a voice carrying) as ambient weather.
///
/// `depth` (0 → 1) is how far the user has come. The sun rises and warms as
/// it grows, so the brightest light lands on the commitment — the inverse of
/// a night app whose sky deepens toward sleep. Animate changes to it slowly;
/// the stage should drift, never jump.
struct MorningStage: View {
    var depth: Double = 0
    var ripples = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let sunCenter = CGPoint(x: size.width / 2, y: size.height * (1.12 - 0.10 * depth))
            let sunRadius = size.width * (0.95 + 0.55 * depth)

            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Palette.skyCrown, location: 0),
                        .init(color: Palette.skyHigh, location: 0.28),
                        .init(color: Palette.skyMid, location: 0.55),
                        .init(color: Palette.skyLow, location: 0.80),
                        .init(color: Palette.skyBase, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // The sunrise. A radial glow anchored below the fold; its
                // reach and warmth are the only things depth changes. Painted
                // normally, not multiplied — multiply compounds chroma and
                // turned the bottom of the screen salmon.
                RadialGradient(
                    stops: [
                        .init(color: Palette.sun.opacity(0.9), location: 0),
                        .init(color: Palette.glow.opacity(0.30 + 0.20 * depth), location: 0.45),
                        .init(color: Palette.glow.opacity(0), location: 1),
                    ],
                    center: UnitPoint(x: sunCenter.x / max(size.width, 1), y: sunCenter.y / max(size.height, 1)),
                    startRadius: 0,
                    endRadius: sunRadius
                )
                .opacity(0.55 + 0.45 * depth)

                if ripples {
                    RippleField(center: sunCenter, reach: size.height * 0.95, animated: !reduceMotion)
                }

                GrainOverlay()
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Concentric rings expanding off the sun and fading as they travel —
/// three at a time, a slow 9s cycle. Quiet enough to live behind text.
private struct RippleField: View {
    let center: CGPoint
    let reach: CGFloat
    let animated: Bool

    private static let period: Double = 9
    private static let count = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated)) { timeline in
            let t = animated ? timeline.date.timeIntervalSinceReferenceDate : 2.2
            Canvas { context, _ in
                for index in 0..<Self.count {
                    let phase = (t / Self.period + Double(index) / Double(Self.count)).truncatingRemainder(dividingBy: 1)
                    let radius = reach * (0.28 + 0.72 * phase)
                    // Fade in over the first tenth, then out as it travels.
                    let alpha = min(phase / 0.1, 1) * pow(1 - phase, 1.6) * 0.16
                    let rect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius * 0.62,
                        width: radius * 2,
                        height: radius * 1.24
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(Palette.coral.opacity(alpha)),
                        lineWidth: 1.2
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A fine paper grain so large gradients never band and the ground reads as
/// a material. Generated once, tiled.
private struct GrainOverlay: View {
    var body: some View {
        Rectangle()
            .fill(ImagePaint(image: Image(uiImage: Self.tile), scale: 0.5))
            .opacity(0.05)
            .blendMode(.multiply)
            .allowsHitTesting(false)
    }

    private static let tile: UIImage = {
        let side = 128
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            var generator = SeededGenerator(seed: 0x5EED)
            for y in 0..<side {
                for x in 0..<side {
                    let value = CGFloat(Double.random(in: 0...1, using: &generator))
                    UIColor(white: value, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()
}

/// Deterministic grain, so the paper looks identical on every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
