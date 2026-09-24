import SwiftUI

/// The pre-app gate. Two doors from welcome: "Get started" runs the flow and
/// ends in an account; "I already have an account" signs in. A signed-in
/// account that was never set up lands straight on the flow, without the
/// account step.
struct OnboardingGate: View {
    let model: AppModel

    @State private var route: Route
    /// How far the sun has risen, 0 → 1. Welcome sits at the quiet end; the
    /// flow reports its own progress so the light peaks on the commitment.
    @State private var depth: Double = 0

    private enum Route: Equatable { case welcome, flow, signIn }

    init(model: AppModel, startAtSignIn: Bool = false) {
        self.model = model
        #if DEBUG
        let reviewing = LaunchFlags.value("-review-onboarding-step") != nil
        #else
        let reviewing = false
        #endif
        _route = State(initialValue: startAtSignIn ? .signIn : model.phase == .needsSetup || reviewing || OnboardingFlow.hasDraft ? .flow : .welcome)
    }

    var body: some View {
        ZStack {
            MorningStage(depth: depth)
                .animation(.easeInOut(duration: 1.1), value: depth)

            switch route {
            case .welcome:
                WelcomeView(
                    onGetStarted: {
                        Analytics.action("welcome")
                        go(.flow)
                    },
                    onSignIn: { go(.signIn) }
                )
                .transition(.opacity)
                .onAppear { Analytics.enter("welcome") }
            case .flow:
                OnboardingFlow(
                    model: model,
                    includesAccount: model.phase != .needsSetup,
                    onExit: model.phase == .needsSetup ? nil : { go(.welcome) },
                    onProgress: { depth = $0 }
                )
                .transition(.opacity)
            case .signIn:
                SignInView(model: model, onBack: { go(.welcome) })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: route)
        // Load the input frameworks while the gate idles, flash-free, so the
        // name step's first keyboard doesn't pay the cold path.
        .onAppear { Keyboard.warmFrameworks() }
        // Signing in to an account with no setup: run the flow (without its
        // account step) instead of leaving the user on sign-in.
        .onChange(of: model.phase) { _, phase in
            if phase == .needsSetup, route != .flow { go(.flow) }
        }
    }

    private func go(_ next: Route) {
        if next != .flow { depth = next == .welcome ? 0 : 0.3 }
        withAnimation(.easeInOut(duration: 0.28)) { route = next }
    }
}
