import SwiftUI

enum AuthIntent {
    case signUp, signIn

    var apple: String { self == .signUp ? String(localized: "Sign up with Apple", bundle: AppLanguage.bundle) : String(localized: "Sign in with Apple", bundle: AppLanguage.bundle) }
    var google: String { self == .signUp ? String(localized: "Sign up with Google", bundle: AppLanguage.bundle) : String(localized: "Sign in with Google", bundle: AppLanguage.bundle) }
}

// MARK: - Welcome

/// The first screen: brand mark, name, one line — and two doors. Built to the
/// `BrandHeroGeometry` contract so it cross-fades into "Welcome back" with
/// the mark holding perfectly still.
///
/// Arriving from the splash, it takes over the splash's mark and name where
/// they stand — the splash is this same frame with the hero lowered to the
/// centre — then glides them up into place while the line and the doors
/// come in beneath.
struct WelcomeView: View {
    let onGetStarted: () -> Void
    let onSignIn: () -> Void

    @State private var heroSettled: Bool
    @State private var detailsShown: Bool

    init(arrivesFromSplash: Bool = false, onGetStarted: @escaping () -> Void, onSignIn: @escaping () -> Void) {
        self.onGetStarted = onGetStarted
        self.onSignIn = onSignIn
        _heroSettled = State(initialValue: !arrivesFromSplash)
        _detailsShown = State(initialValue: !arrivesFromSplash)
    }

    var body: some View {
        WelcomeFrame(heroOffset: heroSettled ? 0 : BrandHeroGeometry.splashLift, detailsVisible: detailsShown) {
            BrandMark(size: BrandHeroGeometry.markSize)
        } name: {
            Text(BrandHeroGeometry.wordmark)
                .font(Typeface.hero(40))
                .foregroundStyle(Palette.ink)
        } footer: {
            VStack(spacing: Space.md) {
                PrimaryButton(title: String(localized: "Get started", bundle: AppLanguage.bundle), action: onGetStarted)
                QuietButton(title: String(localized: "I already have an account", bundle: AppLanguage.bundle), action: onSignIn)
            }
            .allowsHitTesting(detailsShown)
        }
        .task {
            guard !heroSettled else { return }
            try? await Task.sleep(for: .milliseconds(120))
            Haptics.soft(0.5)
            withAnimation(.spring(duration: 1.1, bounce: 0.08)) { heroSettled = true }
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.easeOut(duration: 0.9)) { detailsShown = true }
        }
    }
}

/// Welcome's layout, shared with the splash so the two agree to the pixel:
/// the invisible chevron row, the hero block centred between it and the
/// bottom band, and the band itself. `heroOffset` lowers the block from its
/// place; `detailsVisible` shows the tagline and the footer.
struct WelcomeFrame<Mark: View, Name: View, Footer: View>: View {
    var heroOffset: CGFloat = 0
    var detailsVisible = true
    @ViewBuilder var mark: Mark
    @ViewBuilder var name: Name
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            // Invisible twin of the sign-in screen's chevron header.
            HStack {
                GlassBackButton {}.hidden()
                Spacer()
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.md)
            .accessibilityHidden(true)

            Spacer()

            VStack(spacing: Space.lg) {
                mark
                VStack(spacing: Space.md) {
                    name
                    Text("Practice the conversations that matter.")
                        .font(Typeface.body(16))
                        .foregroundStyle(Palette.dim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 300)
                        .opacity(detailsVisible ? 1 : 0)
                        .offset(y: detailsVisible ? 0 : 8)
                        .accessibilityHidden(!detailsVisible)
                }
                .frame(height: BrandHeroGeometry.textBandHeight, alignment: .top)
            }
            .padding(.horizontal, Space.xxl)
            .offset(y: heroOffset)

            Spacer()

            footer
                .frame(height: BrandHeroGeometry.bottomBandHeight, alignment: .bottom)
                .padding(.horizontal, Space.xxl)
                .padding(.bottom, Space.xxl)
                .opacity(detailsVisible ? 1 : 0)
                .offset(y: detailsVisible ? 0 : 18)
        }
        // No text input here, so keyboard frames must never move this layout.
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Sign in

/// The returning-user door: chevron back to welcome, then the same hero
/// block and provider stack as the welcome screen's geometry.
struct SignInView: View {
    let model: AppModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                GlassBackButton {
                    Keyboard.dismiss()
                    onBack()
                }
                Spacer()
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.md)

            AuthMethodsView(model: model, intent: .signIn, showsBrandMark: true) {
                Keyboard.dismiss()
                onBack()
            }
            .padding(.horizontal, Space.xxl)
        }
        .onAppear { Analytics.enter("sign_in") }
    }
}

// MARK: - Auth methods

/// Apple or Google — nothing else. No passwords to create, forget or reset,
/// no confirmation emails, no second path to maintain: both providers hand
/// back a verified identity in one sheet. Single-purpose by `intent`, with no
/// sign-up/sign-in toggle (the user already chose a door on welcome).
/// Rendered standalone by `SignInView` and as the sign-up flow's final step.
struct AuthMethodsView: View {
    let model: AppModel
    let intent: AuthIntent
    /// On for the standalone sign-in screen; off inside the sign-up flow,
    /// where the header already carries the mark.
    var showsBrandMark = false
    /// Where the left-edge swipe leads.
    var onSwipeBack: (() -> Void)?

    @State private var busy: Provider?
    @State private var message: String?

    private enum Provider { case apple, google }

    private var title: String { intent == .signIn ? String(localized: "Welcome back", bundle: AppLanguage.bundle) : String(localized: "Save your plan", bundle: AppLanguage.bundle) }
    private var subtitle: String {
        intent == .signIn
            ? String(localized: "Sign in to pick up where you left off.", bundle: AppLanguage.bundle)
            : String(localized: "Create a free account so your plan and progress follow you to any device.", bundle: AppLanguage.bundle)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Space.lg) {
                if showsBrandMark {
                    BrandMark(size: BrandHeroGeometry.markSize)
                }
                VStack(spacing: Space.md) {
                    Text(title)
                        .font(Typeface.hero(30))
                        .foregroundStyle(Palette.ink)
                    Text(subtitle)
                        .font(Typeface.body(16))
                        .foregroundStyle(Palette.dim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 300)
                }
                .frame(height: showsBrandMark ? BrandHeroGeometry.textBandHeight : nil, alignment: .top)
            }

            Spacer()

            if let message {
                Text(message)
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, Space.md)
            }

            providers
                .padding(.bottom, Space.xxl)
        }
        .frame(maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: message)
        .swipeBack {
            guard let onSwipeBack else { return }
            Haptics.soft()
            onSwipeBack()
        }
    }

    /// Two buttons that read as one set: equal 58pt height, one label style,
    /// matching white pills with the official marks. The app's coral is
    /// reserved for its own actions, never a third-party provider.
    private var providers: some View {
        VStack(spacing: Space.md) {
            ProviderButton(title: intent.apple, isLoading: busy == .apple) {
                Image(systemName: "apple.logo").resizable().scaledToFit().foregroundStyle(Palette.ink)
            } action: {
                run(.apple) { try await AuthService.signInWithApple() }
            }
            ProviderButton(title: intent.google, isLoading: busy == .google) {
                Image("GoogleLogo").resizable().renderingMode(.original).scaledToFit()
            } action: {
                run(.google) { try await AuthService.signInWithGoogle() }
            }
        }
        .disabled(busy != nil)
    }

    private func run(_ provider: Provider, _ work: @escaping () async throws -> Void) {
        guard busy == nil else { return }
        busy = provider
        message = nil
        Analytics.action(intent == .signUp ? "sign_up" : "sign_in")
        let method = provider == .apple ? "apple" : "google"
        Task {
            do {
                try await work()
                Haptics.success()
                Analytics.capture("auth_completed", ["method": method, "intent": intent == .signUp ? "sign_up" : "sign_in"])
            } catch let failure as AuthFailure {
                if failure != .cancelled {
                    message = failure.errorDescription
                    Haptics.error()
                    Analytics.capture("auth_failed", ["method": method])
                }
            } catch {
                message = String(localized: "Something went wrong. Please try again.", bundle: AppLanguage.bundle)
            }
            busy = nil
        }
    }
}

private struct ProviderButton<Icon: View>: View {
    let title: String
    let isLoading: Bool
    @ViewBuilder let icon: Icon
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            ZStack {
                HStack(spacing: Space.sm) {
                    icon.frame(width: 20, height: 20)
                    Text(title).font(Typeface.label(18))
                }
                .opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(Palette.ink) }
            }
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(Capsule())
        }
        .buttonStyle(ProviderPressStyle())
    }
}

private struct ProviderPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule(style: .continuous).fill(Color.white))
            .shadow(color: Palette.ink.opacity(0.07), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Existing account

/// The answer to "Get started" when the Apple or Google identity behind it
/// already had an account. Those grants are find-or-create, so the app can't
/// refuse up front; by the time it knows, the
/// user is signed in and their real profile is back. This screen refuses to
/// pretend nothing happened — one line of reassurance, one button. The
/// answers they just gave were *not* saved over their plan.
struct ExistingAccountView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            BrandMark(size: BrandHeroGeometry.markSize)
            Text("You already have an account")
                .font(Typeface.hero(28))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.top, Space.xxl)
            Text("We signed you in instead. Your plan and progress are just as you left them.")
                .font(Typeface.body(15))
                .foregroundStyle(Palette.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.md)
            Spacer()
            PrimaryButton(title: String(localized: "Continue to my account", bundle: AppLanguage.bundle), action: onContinue)
                .padding(.bottom, Space.huge)
        }
        .padding(.horizontal, Space.xxl)
        .onAppear { Analytics.enter("existing_account") }
    }
}
