import SwiftUI

/// The gate chain: onboarding → account → **paywall** → microphone →
/// reminders → "You're all set!" → Home.
///
/// Nothing past the paywall is reachable without access — the practice
/// server enforces the same rule, so this is the experience, not the lock.
/// The paywall only ever renders off a *resolved* "not entitled"; while
/// access is unknown the splash holds instead of guessing.
struct RootView: View {
    @State private var model = AppModel()
    @State private var launch: SessionLaunch?

    @State private var splashHoldDone = false
    @State private var micDone = !SetupChain.needsMicrophone
    @State private var remindersNeeded: Bool?
    @State private var remindersDone = false
    @State private var setupDone = false

    /// A deliberately lagged copy of `screen`. The outgoing screen fades to
    /// nothing, the swap happens behind a blank frame, then the new one
    /// fades up — so two screens are never mounted at once (a plain
    /// cross-fade overlaps them and briefly breaks hit-testing).
    @State private var displayedScreen: Screen = .splash
    @State private var contentVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Held long enough that the bloom is actually *seen* breathing — the
    /// Keychain restore usually resolves in well under a second.
    private static let splashHold: Duration = .seconds(1.5)

    fileprivate enum Screen: Equatable {
        case splash, onboarding, existingAccount, paywall, microphone, reminders, setupComplete, main
    }

    private var screen: Screen {
        guard splashHoldDone else { return .splash }
        switch model.phase {
        case .launching: return .splash
        case .signedOut, .needsSetup: return .onboarding
        case .existingAccount: return .existingAccount
        case .ready:
            switch model.subscriptions.access {
            case .unknown: return .splash
            case .notEntitled: return .paywall
            case .entitled:
                if !micDone { return .microphone }
                guard let remindersNeeded else { return .splash }
                if remindersNeeded, !remindersDone { return .reminders }
                if !setupDone, SetupChain.needsCompletion(userID: model.userID) { return .setupComplete }
                return .main
            }
        }
    }

    var body: some View {
        ZStack {
            #if DEBUG
            if LaunchFlags.has("-review-gallery") {
                DesignGallery()
            } else if LaunchFlags.value("-review-onboarding-step") != nil {
                OnboardingGate(model: model)
            } else if let review = LaunchFlags.value("-review-screen") {
                ReviewScreens(name: review, model: model)
            } else {
                routed
            }
            #else
            routed
            #endif
        }
        .task {
            #if DEBUG
            if LaunchFlags.value("-review-screen") != nil { return }
            #endif
            model.start()
            remindersNeeded = await SetupChain.needsReminders()
        }
        .task {
            try? await Task.sleep(for: Self.splashHold)
            splashHoldDone = true
        }
        .task(id: screen) {
            guard screen != displayedScreen else { return }
            guard !reduceMotion else { displayedScreen = screen; return }
            withAnimation(.easeIn(duration: 0.15)) { contentVisible = false }
            try? await Task.sleep(for: .seconds(0.15))
            displayedScreen = screen
            withAnimation(.easeOut(duration: 0.30)) { contentVisible = true }
        }
        .fullScreenCover(item: $launch) { launch in
            sessionView(for: launch)
        }
        // A rehearsal cut short (crash, dropped call, killed app) is offered
        // back the next time Home appears, so spoken words are never lost.
        .onChange(of: displayedScreen) { _, screen in
            guard screen == .main, launch == nil, let userID = model.userID,
                  let draft = PracticeDrafts.load(userID: userID) else { return }
            if draft.hasUserWords { launch = .recover(draft) } else { PracticeDrafts.clear(userID: userID) }
        }
    }

    @ViewBuilder
    private var routed: some View {
        ZStack {
            // The shared ground for every gate after onboarding.
            if displayedScreen != .onboarding && displayedScreen != .main {
                MorningStage(depth: displayedScreen == .splash ? 0 : 1, ripples: displayedScreen != .splash)
            }

            Group {
                switch displayedScreen {
                case .splash:
                    BloomMark(size: 110)
                case .onboarding:
                    OnboardingGate(model: model)
                        .id(model.phase == .needsSetup)
                case .existingAccount:
                    ExistingAccountView { model.acknowledgeExistingAccount() }
                case .paywall:
                    PaywallView(model: model)
                case .microphone:
                    MicrophonePrimerView { micDone = true }
                case .reminders:
                    RemindersPrimerView(practiceTitle: upNextTitle) { remindersDone = true }
                case .setupComplete:
                    SetupCompleteView(model: model) { setupDone = true }
                case .main:
                    MainShellView(model: model, onStart: { launch = .new($0) }, onOpenReport: { launch = .report($0) })
                }
            }
            .transition(.identity)
            .opacity(contentVisible ? 1 : 0)
        }
        .statusBarScrim()
    }

    @ViewBuilder
    private func sessionView(for launch: SessionLaunch) -> some View {
        if let userID = model.userID {
            let finished = { Task { await model.history.load(userID: userID) } }
            switch launch {
            case .new(let setup):
                PracticeSessionView(
                    session: PracticeSession(setup: setup, language: model.profile?.language ?? "en", userID: userID) { _ = finished() },
                    canRetry: canRetry,
                    onClose: { self.launch = nil }
                )
            case .recover(let draft):
                PracticeSessionView(
                    session: PracticeSession(draft: draft, userID: userID) { _ = finished() },
                    canRetry: canRetry,
                    onClose: { self.launch = nil }
                )
            case .report(let report):
                PracticeSessionView(
                    session: PracticeSession(report: report, userID: userID) { _ = finished() },
                    canRetry: canRetry,
                    onClose: { self.launch = nil }
                )
            }
        }
    }

    /// One focused retry per rehearsal, as the server enforces.
    private func canRetry(_ reportID: UUID) -> Bool {
        !model.history.retriedIDs.contains(reportID)
    }

    private var upNextTitle: String? {
        PracticeCatalog.definition(model.profile?.moment?.firstPracticeID ?? "")?.title
    }
}

/// What the practice cover was opened for.
enum SessionLaunch: Identifiable {
    case new(PracticeSetup)
    case recover(PracticeDraft)
    /// Reopening a past rehearsal's debrief (and, from there, its retry).
    case report(PracticeReport)

    var id: String {
        switch self {
        case .new(let setup): "new-\(setup.id)"
        case .recover(let draft): "recover-\(draft.context.attemptId)"
        case .report(let report): "report-\(report.id)"
        }
    }
}

enum LaunchFlags {
    static func has(_ flag: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
    }

    static func value(_ prefix: String) -> String? {
        ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix(prefix + "=") }
            .map { String($0.dropFirst(prefix.count + 1)) }
    }
}
