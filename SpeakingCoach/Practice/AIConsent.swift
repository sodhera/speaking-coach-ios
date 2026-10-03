import SwiftUI

/// Versioned, account-specific permission. A broader disclosure must use a new
/// version so an earlier, narrower agreement cannot authorize new data sharing.
@MainActor
enum AIConsent {
    static let version = 2
    private(set) static var userID: UUID?
    private static var key: String? {
        userID.map { "sc.aiConsent.v\(version).\($0.uuidString.lowercased())" }
    }

    static func identify(_ userID: UUID?) { self.userID = userID }
    static var isGiven: Bool {
        key.map { UserDefaults.standard.bool(forKey: $0) } ?? false
    }

    static func give() {
        guard let key else { return }
        UserDefaults.standard.set(true, forKey: key)
        Analytics.action("ai_consent")
    }

    static func revoke() {
        guard let key else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Checked by every AI transport before any request or voice connection.
    static func require(userID expectedUserID: UUID? = nil) throws {
        guard expectedUserID == nil || expectedUserID == userID else { throw PracticeAPIError.aiConsentRequired }
        guard isGiven else { throw PracticeAPIError.aiConsentRequired }
    }

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
                    onAgree: { withAnimation(.easeInOut(duration: 0.3)) { given = AIConsent.isGiven } },
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
struct AIConsentView: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Kicker(text: "Your privacy", color: Palette.coralDeep)
                    Text("Practice with AI")
                        .font(Typeface.title(28))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("With your permission, these two services help you practice and get feedback.")
                        .font(Typeface.body(16))
                        .foregroundStyle(Palette.dim)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: Space.md) {
                        ServiceRow(systemImage: "waveform", name: "ElevenLabs", role: "Your live and recorded voice, practice context, and any CV, job post or interview notes you add — for conversations and transcription.")
                        Divider().overlay(Palette.border)
                        ServiceRow(systemImage: "text.bubble", name: "OpenAI", role: "Your transcripts, custom situations, slides, presentation setup, slide timing and answers — for questions and feedback.")
                    }
                    .padding(Space.lg)
                    .glassSurface(cornerRadius: Corner.lg)
                    .padding(.top, Space.sm)

                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Only when you use these features. PowerPoint files go to our server for conversion. You can change permission anytime in Settings.")
                            .foregroundStyle(Palette.dim)
                        Link("How AI uses your data", destination: AppConfig.aiDataURL)
                            .foregroundStyle(Palette.coralDeep)
                        Link("Privacy Policy", destination: AppConfig.privacyURL)
                            .foregroundStyle(Palette.coralDeep)
                    }
                    .font(Typeface.body(14))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xl)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: Space.sm) {
                PrimaryButton(title: "Allow and continue") {
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
