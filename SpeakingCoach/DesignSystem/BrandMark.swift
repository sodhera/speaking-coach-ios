import SwiftUI

/// The app icon: a speaker and their speech bubble on coral. Used where the
/// brand introduces itself — the splash, sign-in, the language picker, the
/// onboarding header, the plan. It isn't a voice signal; `VoiceRods` is.
struct BrandMark: View, Animatable {
    /// Width of the mark's square frame.
    var size: CGFloat
    /// 0 hides the mark, 1 shows it whole. Animatable, so a spring past 1
    /// swells it a touch before it settles.
    var openness: Double = 1

    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: Palette.coral.opacity(0.28), radius: size * 0.12, y: size * 0.05)
            .scaleEffect(0.7 + 0.3 * openness)
            .opacity(min(1, max(0, openness)))
            .accessibilityHidden(true)
    }
}

/// The voice, drawn as glass rods in the Continue button's coral. Quiet, they
/// breathe low; while someone speaks (`live`) each swells with the level on
/// its own beat, the beats travelling outward from the middle. On iOS 26 they
/// are real Liquid Glass in one container, so rods that swell close together
/// melt into each other the way the system's glass does.
struct VoiceRods: View {
    /// Width of the rods' square frame.
    var size: CGFloat
    /// The glass's colour. Coral by default; muted while paused, sage on a pass.
    var color: Color = Palette.coral
    /// Live audio level, 0 → 1, smoothed by the caller.
    var level: Double = 0
    /// Someone is speaking: the rods follow `level`.
    var live = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            container { rods(time: t) }
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .animation(.smooth(duration: 0.55), value: live)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func container<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: size * 0.05) { content() }
        } else {
            content()
        }
    }

    /// Seven rods, tallest in the middle, as on a waveform.
    private func rods(time t: Double) -> some View {
        let profile: [CGFloat] = [0.30, 0.52, 0.76, 1, 0.76, 0.52, 0.30]
        let widths: [CGFloat] = [0.075, 0.09, 0.105, 0.125, 0.105, 0.09, 0.075]
        let tallest = size * 0.68
        let voice = live ? min(1, level * 1.5) : 0
        return HStack(alignment: .center, spacing: size * 0.042) {
            ForEach(profile.indices, id: \.self) { index in
                let distance = Double(abs(index - 3))
                let beat = 0.5 + 0.5 * sin(t * 7.2 - distance * 1.1 + Double(index) * 0.35)
                let idle = 0.34 + 0.05 * sin(t * 1.8 - distance * 0.7)
                let reach = idle + (1 - idle) * voice * (0.45 + 0.55 * beat)
                glassPiece(id: "rod\(index)")
                    .frame(width: size * widths[index], height: max(size * widths[index], tallest * profile[index] * CGFloat(reach)))
            }
        }
    }

    /// One rod of coral glass. On iOS 26 it's the system's own Liquid Glass,
    /// tinted; earlier, a gradient with a gloss that reads the same.
    @ViewBuilder
    private func glassPiece(id: String) -> some View {
        let shape = Capsule(style: .continuous)
        let gloss = LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0)], startPoint: .top, endPoint: .center)
        if #available(iOS 26.0, *) {
            shape.fill(gloss)
                .glassEffect(.regular.tint(color), in: shape)
                .glassEffectID(id, in: glass)
        } else {
            shape.fill(LinearGradient(colors: [color.opacity(0.82), color], startPoint: .top, endPoint: .bottom))
                .overlay { shape.fill(gloss) }
                .overlay { shape.stroke(.white.opacity(0.45), lineWidth: max(0.5, size * 0.006)) }
                .shadow(color: color.opacity(0.3), radius: size * 0.05, y: size * 0.02)
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        BrandMark(size: 120)
        VoiceRods(size: 150, level: 0.8, live: true)
        BrandMark(size: 30)
    }
    .padding()
    .background(MorningStage(depth: 0.4))
}
