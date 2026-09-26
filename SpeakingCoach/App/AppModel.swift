import Foundation
import Observation
import Supabase

/// App-wide state: who is signed in, what we know about them, and therefore
/// which screen the root shows. Views never talk to Supabase directly for
/// these facts — they read this model.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        /// Restoring the Keychain session / fetching the profile.
        case launching
        /// No account on this device: welcome → onboarding → account.
        case signedOut
        /// Signed in, but this account has never been through setup.
        case needsSetup
        /// "Get started" signed in to an account that already existed. Its
        /// plan was kept, not overwritten; the user acknowledges before Home.
        case existingAccount
        /// Signed in and set up.
        case ready
    }

    private(set) var phase: Phase = .launching
    private(set) var userID: UUID?
    private(set) var email: String?
    private(set) var profile: CoachProfile?
    let subscriptions = Subscriptions()
    let history = PracticeHistory()
    let presentations = PresentationStore()
    let preparation = PreparationStore()
    let routine = RoutineStore()

    /// Answers finished on the commit step before an account existed. Saved
    /// to the account the moment one appears.
    private var pendingAnswers: OnboardingAnswers?

    private var authTask: Task<Void, Never>?

    func start() {
        guard authTask == nil else { return }
        subscriptions.configure()
        authTask = Task { [weak self] in
            for await (event, session) in Backend.supabase.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .initialSession, .signedIn, .signedOut, .userDeleted:
                    await self.apply(session: session)
                default:
                    break
                }
            }
        }
    }

    /// Called by the onboarding when the user commits. If they're already
    /// signed in (quick setup after sign-in) this saves immediately;
    /// otherwise it waits for the account step.
    func commitOnboarding(_ answers: OnboardingAnswers) {
        if let userID {
            let profile = answers.profile()
            adopt(profile)
            phase = .ready
            OnboardingFlow.clearDraft()
            Task { await ProfileService.save(profile, userID: userID) }
        } else {
            pendingAnswers = answers
        }
    }

    func signOut() async throws {
        try await AuthService.signOut()
    }

    /// "How did you hear about us?" — saved once, on the account.
    func saveAttribution(_ source: AcquisitionSource) {
        guard var profile, let userID else { return }
        profile.heardFrom = source
        self.profile = profile
        Task { await ProfileService.save(profile, userID: userID) }
    }

    func acknowledgeExistingAccount() {
        phase = .ready
    }

    /// The one language for everything: the screens, the partner, the
    /// feedback. Saved on the account so the server's reports match it.
    func changeLanguage(to code: String) {
        Analytics.languageChosen(code, from: "settings")
        LanguageState.shared.choose(code)
        syncLanguage()
        // Session titles in history are read in the language they're shown in.
        if let userID { Task { await history.load(userID: userID) } }
    }

    /// The device's choice wins over the account's. An account restored on a
    /// phone where nothing was chosen yet (an update from the old app, a
    /// sign-in on a new phone) takes the account's language instead.
    private func syncLanguage() {
        guard var profile, let userID else { return }
        if AppLanguage.chosen == nil {
            let adopted = AppLanguage.supported.contains(profile.language) ? profile.language : AppLanguage.code
            LanguageState.shared.choose(adopted)
        }
        guard profile.language != AppLanguage.code else { return }
        profile.language = AppLanguage.code
        self.profile = profile
        ProfileService.cache(profile, userID: userID)
        Task { await ProfileService.save(profile, userID: userID) }
    }

    /// Every path that sets the profile ends here.
    private func adopt(_ profile: CoachProfile) {
        self.profile = profile
        syncLanguage()
        Analytics.identify(userID: userID, profile: self.profile)
    }

    /// The first plan's last step: readiness asked again, saved beside the
    /// baseline it's read against.
    func completePlan(readiness: Int) {
        guard var profile, let userID else { return }
        profile.planReadiness = readiness
        profile.planCompletedAt = .now
        self.profile = profile
        Task { await ProfileService.save(profile, userID: userID) }
    }

    /// Permanently deletes the account through the server, which removes the
    /// user and their data with the service role, then signs out locally.
    func deleteAccount(confirmation: String) async throws {
        let session = try await Backend.supabase.auth.session
        var request = URLRequest(url: AppConfig.apiBaseURL.appending(path: "api/delete-account"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["challengeWord": "DELETE", "confirmationWord": confirmation])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw AuthFailure.message(message ?? String(localized: "Your account couldn't be deleted. Please try again.", bundle: AppLanguage.bundle))
        }
        if let userID { ProfileService.cache(nil, userID: userID) }
        try await AuthService.signOut()
    }

    #if DEBUG
    func setReviewProfile(_ profile: CoachProfile) {
        self.profile = profile
    }

    func setZaraDemoIdentity() {
        var answers = OnboardingAnswers.reviewFixture(before: .account)
        answers.name = "Zara"
        answers.category = .presentations
        answers.moment = .presentation
        profile = answers.profile()
        userID = UUID(uuidString: "A711A711-A711-4711-A711-A711A711A711")
        email = "zara@example.invalid"
        phase = .ready
        history.setReviewRecords([])
    }
    #endif

    // MARK: Session

    private func apply(session: Session?) async {
        // An expired stored session is emitted as the initial session; the
        // SDK refreshes it right behind. Treat it as signed in for routing.
        guard let session else {
            userID = nil
            email = nil
            profile = nil
            history.reset()
            preparation.clearLocal()
            // Signed out, nobody can speak to unlock — so nothing stays shut.
            routine.clearOnSignOut()
            Analytics.identify(userID: nil, profile: nil)
            phase = .signedOut
            await subscriptions.identify(nil)
            return
        }

        let user = session.user
        userID = user.id
        email = user.email
        Analytics.identify(userID: user.id, profile: profile)
        // Resolve access alongside the profile, not after it.
        Task { await subscriptions.identify(user) }

        if user.id != history.userID { Task { await history.load(userID: user.id) } }
        Task { await preparation.load(userID: user.id) }

        // A just-finished onboarding. A brand-new account takes the answers.
        // An existing one (Apple/Google are find-or-create, so "Get started"
        // can land in an old account) keeps the plan it already had — the
        // fresh answers never overwrite it — and says so on its own screen.
        if let answers = pendingAnswers {
            pendingAnswers = nil
            OnboardingFlow.clearDraft()
            if !Self.isNewAccount(user), let existing = await ProfileService.fetch(user: user) {
                ProfileService.cache(existing, userID: user.id)
                adopt(existing)
                phase = .existingAccount
                return
            }
            var fresh = answers
            if fresh.name.isEmpty, case .string(let name)? = user.userMetadata["full_name"] { fresh.name = name }
            let profile = fresh.profile()
            adopt(profile)
            phase = .ready
            await ProfileService.save(profile, userID: user.id)
            return
        }

        if let cached = ProfileService.cached(userID: user.id) {
            adopt(cached)
            phase = .ready
            // Refresh quietly in case another device changed it.
            if let remote = await ProfileService.fetch(user: user), remote != cached {
                ProfileService.cache(remote, userID: user.id)
                adopt(remote)
            }
            return
        }

        phase = .launching
        if let remote = await ProfileService.fetch(user: user) {
            ProfileService.cache(remote, userID: user.id)
            adopt(remote)
            phase = .ready
        } else {
            phase = .needsSetup
        }
    }

    /// Supabase stamps the first sign-in at creation; an existing account's
    /// last sign-in is the one that just happened, long after it was created.
    private static func isNewAccount(_ user: User) -> Bool {
        guard let lastSignInAt = user.lastSignInAt else { return true }
        return abs(lastSignInAt.timeIntervalSince(user.createdAt)) < 5
    }
}
