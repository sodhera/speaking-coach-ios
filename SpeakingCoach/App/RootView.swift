import Foundation
import SwiftUI

/// The gate chain: language → onboarding → account → **paywall** → "how did you hear
/// about us?" → microphone → reminders → "You're all set!" → Home.
///
/// Nothing past the paywall is reachable without access — the practice
/// server enforces the same rule, so this is the experience, not the lock.
/// The paywall only ever renders off a *resolved* "not entitled"; while
/// access is unknown the splash holds instead of guessing.
struct RootView: View {
    @State private var model = AppModel()
    @State private var launch: SessionLaunch?
    @State private var availableUpdate: AppUpdateChecker.Update?
    @State private var lastUpdateCheckAt: Date?

    @State private var splashHoldDone = false
    @State private var attributionDone = false
    @State private var micDone = !SetupChain.needsMicrophone
    @State private var remindersNeeded: Bool?
    @State private var remindersDone = false
    @State private var setupDone = false
    /// The hand-off's "Start my first session": Home opens on its briefing.
    @State private var pendingBriefing: PracticeDefinition?
    @State private var links = DeepLinks.shared
    @State private var language = LanguageState.shared
    @Environment(\.scenePhase) private var scenePhase

    /// A deliberately lagged copy of `screen`. The outgoing screen fades to
    /// nothing, the swap happens behind a blank frame, then the new one
    /// fades up — so two screens are never mounted at once (a plain
    /// cross-fade overlaps them and briefly breaks hit-testing).
    @State private var displayedScreen: Screen = .splash
    @State private var contentVisible = true
    /// The splash's own exit: the mark and wordmark swell and dissolve, and
    /// on the way into the app the sunrise fades to the app's flat ground so
    /// Home rises onto the floor it already stands on.
    @State private var splashLeaving = false
    @State private var stageVisible = true
    @State private var arriving = false
    /// Set when the splash hands its hero to welcome, until the next screen
    /// change. The gate reads it only as it is created.
    @State private var welcomeHandoff = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    fileprivate enum Screen: Equatable {
        case splash, language, onboarding, existingAccount, paywall, attribution, microphone, reminders, setupComplete, main
    }

    private var screen: Screen {
        guard splashHoldDone else { return .splash }
        switch model.phase {
        case .launching: return .splash
        case .signedOut, .needsSetup: return language.isChosen ? .onboarding : .language
        case .existingAccount: return .existingAccount
        case .ready:
            switch model.subscriptions.access {
            case .unknown: return .splash
            case .notEntitled: return .paywall
            case .entitled:
                if needsAttribution { return .attribution }
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
            } else if LaunchFlags.has("-zara-demo") {
                ZaraDemoFlow(model: model)
            } else if LaunchFlags.value("-review-onboarding-step") != nil {
                OnboardingGate(model: model)
            } else if LaunchFlags.value("-review-screen") == "signin" {
                if model.userID == nil {
                    OnboardingGate(model: model, startAtSignIn: true)
                } else {
                    routed
                }
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
            if LaunchFlags.has("-zara-demo") { return }
            if let review = LaunchFlags.value("-review-screen"), review != "signin" { return }
            #endif
            model.start()
            remindersNeeded = await SetupChain.needsReminders()
            await checkForAppUpdate()
        }
        .task(id: screen) {
            guard screen != displayedScreen else { return }
            guard !reduceMotion else { displayedScreen = screen; return }
            if displayedScreen == .splash {
                await leaveSplash(for: screen)
                return
            }
            welcomeHandoff = false
            withAnimation(.easeIn(duration: 0.15)) { contentVisible = false }
            try? await Task.sleep(for: .seconds(0.15))
            displayedScreen = screen
            withAnimation(.easeOut(duration: 0.30)) { contentVisible = true }
        }
        .fullScreenCover(item: $launch) { launch in
            sessionView(for: launch)
                .environment(\.stageStyle, .flat)
                .inAppLanguage(language.code)
        }
        .modifier(AppUpdateNotice(availableUpdate: $availableUpdate, isReady: splashHoldDone && launch == nil))
        .onOpenURL { url in
            if url.scheme == AppConfig.authCallback.scheme,
               url.host == AppConfig.authCallback.host,
               url.path == AppConfig.authCallback.path {
                // The in-app ASWebAuthenticationSession handles its own
                // callback. This also covers a callback delivered by iOS
                // after the app was backgrounded or relaunched: Supabase
                // must exchange the code while its persisted PKCE verifier
                // is still available.
                Backend.supabase.auth.handle(url)
            } else {
                links.pending = url
            }
        }
        .onChange(of: links.pending) { _, _ in openPendingLink() }
        .onChange(of: model.userID) { _, _ in openPendingLink() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.routine.reconcile()
                Task { await checkForAppUpdate() }
            }
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
            // Always underneath, so a screen fading in never shows the bare
            // window. It turns flat as the splash heads into the app.
            MorningStage(depth: 0)
                .environment(\.stageStyle, displayedScreen == .main || !stageVisible ? .flat : .morning)
            // The shared ground for every gate after onboarding.
            if displayedScreen != .onboarding && displayedScreen != .main {
                // Ripples on the splash too: they run on the clock, so they
                // carry straight on into welcome's own stage.
                MorningStage(depth: displayedScreen == .splash ? 0 : 1)
                    .opacity(stageVisible ? 1 : 0)
            }

            Group {
                switch displayedScreen {
                case .splash:
                    SplashView(plays: !splashHoldDone) { splashHoldDone = true }
                        .scaleEffect(splashLeaving ? 1.06 : 1)
                        .blur(radius: splashLeaving ? 12 : 0)
                        .opacity(splashLeaving ? 0 : 1)
                case .language:
                    LanguagePickerView { code in
                        Analytics.languageChosen(code, from: "first_run")
                        language.choose(code)
                    }
                case .onboarding:
                    OnboardingGate(model: model, fromSplash: welcomeHandoff)
                        .id(model.phase == .needsSetup)
                case .existingAccount:
                    ExistingAccountView { model.acknowledgeExistingAccount() }
                case .paywall:
                    PaywallView(model: model)
                case .attribution:
                    AttributionView { source in
                        model.saveAttribution(source)
                        attributionDone = true
                    }
                case .microphone:
                    MicrophonePrimerView { micDone = true }
                case .reminders:
                    RemindersPrimerView(practiceTitle: upNextTitle) { remindersDone = true }
                case .setupComplete:
                    SetupCompleteView(model: model) { startFirst in
                        pendingBriefing = startFirst
                        setupDone = true
                    }
                case .main:
                    MainShellView(model: model, pendingBriefing: $pendingBriefing, onStart: { launch = Self.launch(for: $0) }, onOpenReport: { launch = .report($0) }, onStartCustom: { launch = .custom($0, $1) })
                }
            }
            .transition(.identity)
            // A new language rebuilds every screen in it at once.
            .id(language.code)
            .opacity(contentVisible ? 1 : 0)
            .scaleEffect(arriving ? 0.97 : 1)
            .offset(y: arriving ? 12 : 0)
        }
        .statusBarScrim()
        .inAppLanguage(language.code)
        // This scrim sits over every screen, so it takes the app's flat
        // ground once the user is in; the gates keep the sunrise's paper.
        .environment(\.stageStyle, displayedScreen == .main ? .flat : .morning)
    }

    /// Into welcome, nothing fades: welcome mounts with the splash's mark and
    /// name on the same pixels and lifts them into place itself.
    ///
    /// Anywhere else, the splash dissolves outward and what follows rises
    /// into place. Heading into the app, the sunrise fades with it, so Home
    /// arrives on its own flat ground rather than snapping out of the morning
    /// sky. Unhurried on purpose, with a soft tap as it lets go and a fainter
    /// one as the next screen starts to rise.
    private func leaveSplash(for next: Screen) async {
        if next == .onboarding, OnboardingGate.opensOnWelcome(model) {
            welcomeHandoff = true
            displayedScreen = next
            return
        }
        Haptics.soft(0.6)
        withAnimation(.easeInOut(duration: 0.8)) {
            splashLeaving = true
            if next == .main { stageVisible = false }
        }
        try? await Task.sleep(for: .seconds(0.8))
        contentVisible = false
        arriving = true
        displayedScreen = next
        splashLeaving = false
        stageVisible = true
        Haptics.soft(0.35)
        withAnimation(.smooth(duration: 1.1)) {
            contentVisible = true
            arriving = false
        }
    }

    @ViewBuilder
    private func sessionView(for launch: SessionLaunch) -> some View {
        if let userID = model.userID {
            let finished = { Task { await model.history.load(userID: userID) } }
            switch launch {
            case .new(let setup):
                PracticeSessionView(
                    session: PracticeSession(setup: setup, userID: userID) { _ = finished() },
                    canRetry: canRetry,
                    onClose: { self.launch = nil; _ = finished() }
                )
            case .recover(let draft):
                PracticeSessionView(
                    session: PracticeSession(draft: draft, userID: userID) { _ = finished() },
                    canRetry: canRetry,
                    onClose: { self.launch = nil; _ = finished() }
                )
            case .report(let report):
                PracticeSessionView(
                    session: PracticeSession(report: report, userID: userID) { _ = finished() },
                    canRetry: canRetry,
                    onClose: { self.launch = nil; _ = finished() }
                )
            case .custom(let situation, let setup):
                PracticeSessionView(
                    session: PracticeSession(custom: situation, setup: setup, userID: userID) { _ = finished() },
                    onClose: { self.launch = nil; _ = finished() }
                )
            case .prompt(let source):
                PromptView(routine: model.routine, source: source) { self.launch = nil }
            }
        }
    }

    /// Today's prompt, from its reminder or a shielded app. It opens for any
    /// signed-in user — even one whose plan has lapsed — because it's also
    /// the way back into their own apps.
    private func openPendingLink() {
        guard let url = links.pending, model.userID != nil, launch == nil else { return }
        links.pending = nil
        switch url.host() {
        case "unlock": launch = .prompt(.unlock)
        case "prompt": launch = .prompt(.reminder)
        default: break
        }
    }

    @MainActor
    private func checkForAppUpdate() async {
        guard launch == nil,
              availableUpdate == nil,
              lastUpdateCheckAt.map({ Date.now.timeIntervalSince($0) >= 6 * 60 * 60 }) ?? true else { return }
        lastUpdateCheckAt = .now
        availableUpdate = await AppUpdateChecker.availableUpdate()
    }

    /// Asked once per account, after the paywall. Old-app accounts never
    /// went through this onboarding, so they're never asked.
    private var needsAttribution: Bool {
        guard !attributionDone, let profile = model.profile else { return false }
        return !profile.isLegacy && profile.heardFrom == nil
    }

    /// A built-in scene looks like any rehearsal on its briefing, but runs
    /// on the custom-situation path — the catalog server doesn't know it.
    private static func launch(for setup: PracticeSetup) -> SessionLaunch {
        if let situation = CustomSituation.builtIn(for: setup.practice) { return .custom(situation, setup) }
        return .new(setup)
    }

    /// One focused retry per session, as the server enforces: none once it
    /// has ended in feedback or been started on this phone.
    private func canRetry(_ reportID: UUID) -> Bool {
        !model.history.retriedIDs.contains(reportID)
    }

    private var upNextTitle: String? {
        model.profile?.moment?.firstPractice?.title
    }
}

private enum AppUpdateChecker {
    struct Update: Identifiable {
        let version: String
        let storeURL: URL

        var id: String { version }
    }

    private struct LookupResponse: Decodable {
        let results: [Listing]
    }

    private struct Listing: Decodable {
        let bundleId: String
        let version: String
        let trackViewUrl: URL
    }

    static func availableUpdate(for bundle: Bundle = .main) async -> Update? {
        guard let bundleID = bundle.bundleIdentifier,
              let installedVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !bundleID.isEmpty, !installedVersion.isEmpty else { return nil }

        let country = Locale.current.region?.identifier.lowercased() ?? "us"
        if let update = await lookup(bundleID: bundleID, installedVersion: installedVersion, country: country) {
            return update
        }
        guard country != "us" else { return nil }
        return await lookup(bundleID: bundleID, installedVersion: installedVersion, country: "us")
    }

    private static func lookup(bundleID: String, installedVersion: String, country: String) async -> Update? {
        guard var components = URLComponents(string: "https://itunes.apple.com/lookup") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: country),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(LookupResponse.self, from: data),
              let listing = result.results.first(where: { $0.bundleId == bundleID }),
              isNewer(listing.version, than: installedVersion),
              listing.trackViewUrl.host == "apps.apple.com" else { return nil }

        return Update(version: listing.version, storeURL: listing.trackViewUrl)
    }

    private static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let candidateParts = candidate.split(separator: ".").compactMap { Int($0) }
        let installedParts = installed.split(separator: ".").compactMap { Int($0) }
        guard !candidateParts.isEmpty, !installedParts.isEmpty else { return false }

        for index in 0..<max(candidateParts.count, installedParts.count) {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let installedPart = index < installedParts.count ? installedParts[index] : 0
            if candidatePart != installedPart { return candidatePart > installedPart }
        }
        return false
    }
}

private struct AppUpdateNotice: ViewModifier {
    @Binding var availableUpdate: AppUpdateChecker.Update?
    let isReady: Bool

    func body(content: Content) -> some View {
        content.alert(item: Binding(
            get: { isReady ? availableUpdate : nil },
            set: { availableUpdate = $0 }
        )) { update in
            Alert(
                title: Text("Update available"),
                message: Text("Speaking Coach \(update.version) is ready. Update to get the latest improvements."),
                primaryButton: .default(Text("Update now")) {
                    UIApplication.shared.open(update.storeURL)
                },
                secondaryButton: .cancel(Text("Later"))
            )
        }
    }
}

/// The bloom opens from a bud over the morning sky and the name inks itself
/// in beneath it. Laid out on welcome's own frame with the hero lowered to
/// the centre, so when welcome follows it can lift the same mark and name
/// straight into place. Reports done once the name has landed and had a beat
/// to be read, never sooner than the minimum hold — the Keychain restore
/// usually resolves in well under a second, and the bloom should be *seen*.
///
/// Shown again mid-flow (while access resolves), it's already open and named.
private struct SplashView: View {
    let plays: Bool
    let onFinished: () -> Void

    @State private var openness: Double
    @State private var typed = false
    @State private var held = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let minimumHold: Duration = .seconds(1.2)
    private static let readingBeat: Duration = .milliseconds(300)

    init(plays: Bool, onFinished: @escaping () -> Void) {
        self.plays = plays
        self.onFinished = onFinished
        _openness = State(initialValue: plays ? 0 : 1)
    }

    var body: some View {
        WelcomeFrame(heroOffset: BrandHeroGeometry.splashLift, detailsVisible: false) {
            BrandMark(size: BrandHeroGeometry.markSize, openness: openness)
        } name: {
            InkedLine(
                text: BrandHeroGeometry.wordmark,
                font: Typeface.hero(40),
                plays: plays,
                delay: .milliseconds(700),
                onFinished: { typed = true }
            )
        } footer: {
            Color.clear
        }
        .task {
            guard plays else { return }
            if reduceMotion {
                openness = 1
            } else {
                try? await Task.sleep(for: .milliseconds(150))
                Haptics.soft(0.45)
                withAnimation(.spring(duration: 1.3, bounce: 0.22)) { openness = 1 }
            }
            try? await Task.sleep(for: Self.minimumHold)
            held = true
        }
        .task(id: typed && held) {
            guard typed && held else { return }
            try? await Task.sleep(for: Self.readingBeat)
            onFinished()
        }
    }
}

/// What the practice cover was opened for.
enum SessionLaunch: Identifiable {
    case new(PracticeSetup)
    case recover(PracticeDraft)
    /// Reopening a past rehearsal's debrief (and, from there, its retry).
    case report(PracticeReport)
    /// A situation the user described.
    case custom(CustomSituation, PracticeSetup)
    /// Today's speaking prompt.
    case prompt(PromptView.Source)

    var id: String {
        switch self {
        case .new(let setup): "new-\(setup.id)"
        case .recover(let draft): "recover-\(draft.context.attemptId)"
        case .report(let report): "report-\(report.id)"
        case .custom(let situation, _): "custom-\(situation.title)"
        case .prompt(let source): "prompt-\(source.rawValue)"
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

extension View {
    /// Dates, numbers and the reading direction follow the app's language,
    /// not the phone's, from the moment it's chosen.
    func inAppLanguage(_ code: String) -> some View {
        environment(\.locale, Locale(identifier: AppLanguage.localization(for: code)))
            .environment(\.layoutDirection, code == "ar" ? .rightToLeft : .leftToRight)
    }
}
