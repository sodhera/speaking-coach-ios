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
                    Text("Allow AI data sharing?")
                        .font(Typeface.title(28))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("With your permission, Speaking Coach shares the following data with ElevenLabs and OpenAI to provide AI conversations, transcription, questions and feedback.")
                        .font(Typeface.body(16))
                        .foregroundStyle(Palette.dim)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: Space.lg) {
                        ServiceRow(systemImage: "waveform", name: "ElevenLabs", role: "Receives live microphone audio, recorded practice and answer audio, and the practice context you provide, including CV, job post and interview notes. It runs your voice partner and transcribes recordings.")
                        Divider().overlay(Palette.border)
                        ServiceRow(systemImage: "text.bubble", name: "OpenAI", role: "Receives conversation and recording transcripts, custom situations, and presentation slide text, title, audience, instructions, slide timing and answers. It checks situations and generates questions and feedback. Any personal details in this content are included.")
                    }
                    .padding(Space.lg)
                    .glassSurface(cornerRadius: Corner.lg)
                    .padding(.top, Space.sm)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Data is sent through our servers or directly to ElevenLabs when you use these features. PowerPoint files are also uploaded to our server for PDF conversion. Choose Not now to continue without AI features. You can withdraw permission in Settings → AI data sharing. Withdrawal stops future sharing; it does not delete data already sent. Read more in our")
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
                PrimaryButton(title: "Allow AI data sharing") {
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
