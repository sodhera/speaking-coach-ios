import SwiftUI

/// Permission to send what the user says to the AI services that run a
/// practice (App Store Guideline 5.1.2(i)): ElevenLabs hears the voice and
/// plays the partner, OpenAI reads the words for feedback. Asked once, at the
/// first moment anything would be sent — never during onboarding, so it's
/// asked of old-app accounts too.
@MainActor
enum AIConsent {
    private static let key = "sc.aiConsent.v1"

    static var isGiven: Bool { UserDefaults.standard.bool(forKey: key) }

    static func give() {
        UserDefaults.standard.set(true, forKey: key)
        Analytics.action("ai_consent")
    }

    /// Runs `action` now when consent is already given and returns nil;
    /// otherwise returns it to hold until the consent sheet is answered.
    static func gate(_ action: @escaping () -> Void) -> (() -> Void)? {
        guard isGiven else { return action }
        action()
        return nil
    }
}

/// Full-screen content that asks first: the consent screen until it's
/// given, then the content. Declining closes the presentation.
struct AIConsentGate<Content: View>: View {
    let onDecline: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var given = AIConsent.isGiven

    var body: some View {
        if given {
            content()
        } else {
            ZStack {
                MorningStage(depth: 0.8)
                AIConsentView(
                    onAgree: { withAnimation(.easeInOut(duration: 0.3)) { given = true } },
                    onDecline: onDecline
                )
            }
            .statusBarScrim()
        }
    }
}

extension View {
    /// A sheet asking for consent while `pending` holds an action (see
    /// `AIConsent.gate`); agreeing runs it, declining drops it.
    func aiConsentSheet(_ pending: Binding<(() -> Void)?>) -> some View {
        sheet(isPresented: Binding(get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } })) {
            ZStack {
                MorningStage(depth: 0.8)
                AIConsentView(
                    onAgree: {
                        let action = pending.wrappedValue
                        pending.wrappedValue = nil
                        action?()
                    },
                    onDecline: { pending.wrappedValue = nil }
                )
            }
            .presentationDragIndicator(.visible)
        }
    }
}

/// Plain words about where the voice goes, named, before it goes there.
private struct AIConsentView: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Kicker(text: "Before you practice", color: Palette.coralDeep)
                    Text("Your partner is an AI")
                        .font(Typeface.title(28))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("To run the conversation and write your feedback, Speaking Coach sends what you say to two AI services.")
                        .font(Typeface.body(16))
                        .foregroundStyle(Palette.dim)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: Space.lg) {
                        ServiceRow(systemImage: "waveform", name: "ElevenLabs", role: "Hears your voice and answers as your partner, live.")
                        Divider().overlay(Palette.border)
                        ServiceRow(systemImage: "text.bubble", name: "OpenAI", role: "Reads the words you said and writes your feedback.")
                    }
                    .padding(Space.lg)
                    .glassSurface(cornerRadius: Corner.lg)
                    .padding(.top, Space.sm)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("This happens only when you practice. Read more in our")
                            .foregroundStyle(Palette.dim)
                        Link("Privacy Policy", destination: AppConfig.privacyURL)
                            .foregroundStyle(Palette.coralDeep)
                    }
                    .font(Typeface.body(14))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xxxl)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: Space.sm) {
                PrimaryButton(title: "Agree and continue") {
                    AIConsent.give()
                    Haptics.success()
                    onAgree()
                }
                QuietButton(title: "Not now", action: onDecline)
            }
            .padding(.horizontal, Space.xxl)
            .padding(.bottom, Space.lg)
        }
        .onAppear { Analytics.enter("ai_consent") }
    }
}

private struct ServiceRow: View {
    let systemImage: String
    let name: String
    let role: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.coral)
                .frame(width: 24)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Typeface.label(16)).foregroundStyle(Palette.ink)
                Text(role).font(Typeface.body(15)).foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
