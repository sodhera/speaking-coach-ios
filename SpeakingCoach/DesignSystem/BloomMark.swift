import SwiftUI

/// The app icon's six-petal bloom, drawn live.
///
/// At rest the petals breathe in a slow wave that travels around the flower,
/// the way a held breath moves before someone speaks. In the voice room the
/// same mark is the conversation's instrument: `level` (0 → 1, smoothed by
/// the caller) opens the petals with the audio, so the brand and the "it's
/// live" signal are one object.
///
/// Geometry is measured off the 1024pt icon: petals are ellipses 0.325w long
/// and 0.142w thick whose centres sit 0.236w from the middle, at 60° steps
/// starting horizontal.
struct BloomMark: View {
    /// Outer diameter of the flower at rest.
    var size: CGFloat
    var color: Color = Palette.coral
    /// Live audio level, 0 → 1.
    var level: Double = 0
    var breathes = true
    var glow = true

    /// Small marks breathe as one — every petal together, slow and shallow,
    /// like a held breath. A travelling wave deep enough to see at 30pt made
    /// the flower look lopsided, as if it were wobbling rather than alive.
    /// Large marks keep the gentle wave around the flower.
    private var isSmall: Bool { size < 60 }
    private var breathDepth: Double { isSmall ? 0.09 : 0.045 }
    private var breathPeriod: Double { isSmall ? 4.2 : 3.4 }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let extent: CGFloat = 0.236 + 0.325 / 2 // centre → petal tip, in icon widths

    var body: some View {
        let animated = breathes && !reduceMotion
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !animated && level == 0)) { timeline in
            let t = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { context, canvasSize in
                drawPetals(in: &context, canvasSize: canvasSize, time: t, animated: animated)
            }
            .frame(width: size * 1.5, height: size * 1.5)
            .background {
                if glow {
                    Circle()
                        .fill(color.opacity(0.16 + 0.22 * level))
                        .frame(width: size * 1.05, height: size * 1.05)
                        .blur(radius: size * 0.22)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func drawPetals(in context: inout GraphicsContext, canvasSize: CGSize, time t: Double, animated: Bool) {
        let unit: CGFloat = size / (Self.extent * 2)
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        for index in 0..<6 {
            let i = Double(index)
            let angle: Double = i * .pi / 3
            // A wave travelling around the flower, one petal after the next.
            let phase: Double = isSmall ? 0 : angle
            let breath: Double = animated ? breathDepth * sin(t * 2 * .pi / breathPeriod - phase) : 0
            // Voice: every petal opens with the level, each by its own
            // flickering share, so speech reads as texture rather than a
            // uniform pulse.
            let flicker: Double = 0.65 + 0.35 * sin(t * 9 + i * 1.7)
            let open: Double = level * 0.34 * flicker
            let length: CGFloat = 0.325 * unit * CGFloat(1 + breath + open)
            let thickness: CGFloat = 0.142 * unit * CGFloat(1 + open * 0.25)
            // Petals also drift outward a touch as they swell, so the flower
            // opens rather than only lengthening.
            let distance: CGFloat = 0.236 * unit * CGFloat(1 + open * 0.35 + breath * 0.35)

            var petal = context
            petal.translateBy(x: center.x, y: center.y)
            petal.rotate(by: .radians(angle))
            let rect = CGRect(x: distance - length / 2, y: -thickness / 2, width: length, height: thickness)
            petal.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        BloomMark(size: 120)
        BloomMark(size: 120, level: 0.8)
    }
    .padding()
    .background(MorningStage(depth: 0.4))
}
