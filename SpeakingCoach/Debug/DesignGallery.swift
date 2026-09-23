#if DEBUG
import SwiftUI

/// Every design-system component on one screen, for eyeballing on a
/// simulator: `-review-gallery`.
struct DesignGallery: View {
    @State private var depth = 0.5
    @State private var level = LaunchFlags.value("-review-voice-level").flatMap(Double.init) ?? 0
    @State private var single = 1
    @State private var multi: Set<Int> = [0]

    var body: some View {
        ZStack {
            MorningStage(depth: depth)
                .animation(.easeInOut(duration: 1), value: depth)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    HStack {
                        GlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") {}
                        Spacer()
                        GlassIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {}
                    }

                    Kicker(text: "Design system")
                    Text("Your interview is in 5 days.")
                        .font(Typeface.hero(32))
                        .foregroundStyle(Palette.ink)
                    Text("Body copy sits in DM Sans at 17pt, warm dim ink, one line where possible.")
                        .font(Typeface.body(17))
                        .foregroundStyle(Palette.dim)

                    HStack {
                        Spacer()
                        BloomMark(size: 120, level: level)
                        Spacer()
                    }
                    .frame(height: 170)

                    labeled("Stage depth") { Slider(value: $depth) }
                    labeled("Voice level") { Slider(value: $level) }

                    GlassGroup(spacing: Space.md) {
                        VStack(spacing: Space.md) {
                            ForEach(Array(["Job interview", "Asking for a raise", "A presentation"].enumerated()), id: \.offset) { index, title in
                                OptionRow(icon: "briefcase", title: title, isSelected: single == index) { single = index }
                            }
                        }
                    }

                    GlassGroup(spacing: Space.md) {
                        VStack(spacing: Space.md) {
                            ForEach(Array(["I stay calm", "I say it clearly"].enumerated()), id: \.offset) { index, title in
                                OptionRow(icon: "leaf", title: title, isSelected: multi.contains(index)) {
                                    if multi.contains(index) { multi.remove(index) } else { multi.insert(index) }
                                }
                            }
                        }
                    }

                    PrimaryButton(title: "Continue") {}
                    PrimaryButton(title: "Continue", action: {}).disabled(true)
                    PrimaryButton(title: "Loading", isLoading: true) {}
                    SecondaryButton(title: "Adjust practice", systemImage: "slider.horizontal.3") {}
                    QuietButton(title: "I already have an account") {}
                }
                .padding(Space.xxl)
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title).font(Typeface.label(13)).foregroundStyle(Palette.muted)
            content().tint(Palette.coral)
        }
    }
}
#endif
