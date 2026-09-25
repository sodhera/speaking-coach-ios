import SwiftUI
import UIKit

/// The ground every pre-app screen stands on: warm paper sky and a sunrise
/// glowing up from below the bottom edge. (Slow ripple rings once drifted
/// off the sun; they were removed as background noise.)
///
/// `depth` (0 → 1) is how far the user has come. The sun rises and warms as
/// it grows, so the brightest light lands on the commitment — the inverse of
/// a night app whose sky deepens toward sleep. Animate changes to it slowly;
/// the stage should drift, never jump.
struct MorningStage: View {
    var depth: Double = 0


    @Environment(\.stageStyle) private var style

    var body: some View {
        if style == .flat {
            AppGround()
        } else {
            sunrise
        }
    }

    private var sunrise: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let sunCenter = CGPoint(x: size.width / 2, y: size.height * (1.12 - 0.10 * depth))
            let sunRadius = size.width * (0.95 + 0.55 * depth)

            ZStack {
                MorningStage.sky

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

                GrainOverlay()
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension MorningStage {
    static let sky = LinearGradient(
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
}

/// The stage's paper without its sunrise: the same full-screen sky and grain,
/// so a slice of it lies pixel-for-pixel over the real stage. The sun never
/// reaches the top of the screen, which is the only place this is used.
struct MorningPaper: View {
    @Environment(\.stageStyle) private var style

    var body: some View {
        if style == .flat {
            AppGround()
        } else {
            paper
        }
    }

    private var paper: some View {
        ZStack {
            MorningStage.sky
            GrainOverlay()
        }
        // Grain multiplies onto this sky only, never onto what's beneath.
        .compositingGroup()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Which ground a screen stands on. Onboarding, the paywall and the setup
/// gates keep the sunrise: it tells their story, warming as the user
/// commits. The app itself stands on flat ground, so its cards carry the
/// screen and nothing drifts behind the content.
enum StageStyle { case morning, flat }

private struct StageStyleKey: EnvironmentKey {
    static let defaultValue = StageStyle.morning
}

extension EnvironmentValues {
    var stageStyle: StageStyle {
        get { self[StageStyleKey.self] }
        set { self[StageStyleKey.self] = newValue }
    }
}

/// The app's ground: one flat warm tone, no gradient, grain or ripples.
struct AppGround: View {
    var body: some View {
        ground
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var ground: some View {
        #if DEBUG
        if LaunchFlags.value("-ground-style") == "flat" {
            Palette.ground
        } else {
            AppGround.warmLight
        }
        #else
        AppGround.warmLight
        #endif
    }

    /// Warm paper lit faintly from above: a touch lighter at the top than
    /// the bottom, never reaching the old sunrise's tan.
    static let warmLight = LinearGradient(
        colors: [Color(hex: 0xFAF6F2), Color(hex: 0xF3ECE5)],
        startPoint: .top,
        endPoint: .bottom
    )
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
