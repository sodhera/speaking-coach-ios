import SwiftUI

// MARK: - Brand hero geometry

/// The contract between the two brand-hero screens — welcome and "Welcome
/// back". The gate cross-fades one into the other, so the mark must land on
/// *exactly* the same pixel on both; a few points of drift reads as the logo
/// twitching mid-fade. Both screens centre the same-shaped block — mark, `lg`
/// gap, a text band of this fixed height — between a chevron-height header
/// row (welcome renders an invisible twin of sign-in's real chevron) and a
/// bottom band of this fixed height (the provider stack's natural size;
/// welcome bottom-aligns its two smaller controls inside the same band).
enum BrandHeroGeometry {
    static let wordmark = "Speaking Coach"
    static let markSize: CGFloat = 120
    /// Fits welcome's hero and sign-in's title + subtitle alike, with room
    /// for a second line in languages that run longer than English.
    static let textBandHeight: CGFloat = 116
    /// Two 58pt provider buttons (Apple, Google) with one `md` gap.
    static let bottomBandHeight: CGFloat = 58 * 2 + Space.md
    /// How far below its welcome place the splash holds the hero block: half
    /// the difference between the bottom band and the chevron row, which
    /// centres it on the screen.
    static let splashLift: CGFloat = ((bottomBandHeight + Space.xxl) - (44 + Space.md)) / 2
}

// MARK: - Question layout

/// Every onboarding step's shape: the question **centred** at the top, its
/// control centred in the space between the question and the bottom action.
///
/// Centred, not leading — the flow reads as statements addressed to one
/// person, and one axis keeps question, control and readout in a straight
/// line for the eye. No kicker: the title carries the question alone.
struct QuestionLayout<Content: View>: View {
    let title: String
    var subtitle: String?
    /// A live consequence of the control below it. Separate from `subtitle`
    /// because it belongs to the *answer*: under the title it reads as part
    /// of the prompt, and the user has to look away from what they're
    /// changing to see their own number move.
    var readout: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            VStack(alignment: .center, spacing: Space.md) {
                Text(title)
                    .font(Typeface.title(28))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(Typeface.body(15))
                        .foregroundStyle(Palette.dim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: Space.lg)

            VStack(spacing: Space.xl) {
                content
                if let readout {
                    Text(readout)
                        .font(Typeface.body(16))
                        .foregroundStyle(Palette.dim)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.2), value: readout)
                        .frame(maxWidth: .infinity)
                }
            }

            Spacer(minLength: Space.lg)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Page scaffold

/// Every Profile/Settings page sits on the stage with a transparent scroll;
/// the system navigation bar is hidden and sub-pages go back with the round
/// glass chevron, matching onboarding.
struct SceneScreen<Content: View>: View {
    var depth: Double = 0
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            MorningStage(depth: depth)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) { content }
                    // Claim the full width, or the column shrinks to its
                    // widest child and the scroll view centres it.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, 140)
            }
        }
        .statusBarScrim()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Editorial sub-page header: glass chevron above a left-aligned hero title.
struct SubpageHeader: View {
    let title: String
    var subtitle: String?
    var onBack: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            GlassBackButton { onBack?() ?? dismiss() }
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(title)
                    .font(Typeface.hero(28))
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Typeface.body(15))
                        .foregroundStyle(Palette.dim)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Permission primer

/// A stand-in for the real system permission sheet, so the user recognises
/// it on sight and knows which button to press when the real one appears.
/// Its labels and button order mirror the real dialog (affirmative on the
/// right for microphone and notifications). The coral arrow points at the
/// half that fires the real request.
struct MockPermissionDialog: View {
    let glyph: String
    let titleText: String
    var allowTitle = String(localized: "Allow", bundle: AppLanguage.bundle)
    var denyTitle = String(localized: "Don't Allow", bundle: AppLanguage.bundle)
    let isRequesting: Bool
    let onAllow: () -> Void
    let onDeny: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrowLift = false

    var body: some View {
        VStack(spacing: Space.lg) {
            VStack(spacing: 0) {
                VStack(spacing: Space.md) {
                    Image(systemName: glyph)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Palette.dim)
                        .accessibilityHidden(true)
                    Text(titleText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    // Greeked body lines — gesturing at the sheet's copy
                    // without pretending to quote it.
                    VStack(spacing: 5) {
                        Capsule().fill(Palette.hairline).frame(width: 170, height: 6)
                        Capsule().fill(Palette.hairline).frame(width: 128, height: 6)
                    }
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                }
                .padding(Space.xl)

                Rectangle().fill(Palette.hairline).frame(height: 1)

                HStack(spacing: 0) {
                    dialogButton(denyTitle, weight: .regular, color: Palette.muted, action: onDeny)
                    Rectangle().fill(Palette.hairline).frame(width: 1, height: 46)
                    dialogButton(allowTitle, weight: .semibold, color: Color(red: 0.04, green: 0.52, blue: 1.0), action: onAllow)
                        .overlay { if isRequesting { ProgressView() } }
                }
            }
            .frame(maxWidth: 300)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .shadow(color: Palette.ink.opacity(0.12), radius: 24, y: 12)

            // The arrow sits under the half that fires the real request.
            HStack(spacing: 0) {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                Image(systemName: "arrow.up")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.coral)
                    .offset(y: arrowLift ? -6 : 0)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 300)
            .accessibilityHidden(true)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { arrowLift = true }
        }
    }

    private func dialogButton(_ title: String, weight: Font.Weight, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            Text(title)
                .font(.system(size: 17, weight: weight))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRequesting)
    }
}
