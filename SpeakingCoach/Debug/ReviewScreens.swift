#if DEBUG
import SwiftUI

/// `-review-screen=<name>` renders a screen against a fixture profile, with
/// no account or purchase needed: `welcome`, `signin`, `existing`, `paywall`,
/// `microphone`, `reminders`, `setup`, `home`, `profile`, `library`,
/// `briefing`, `settings`.
struct ReviewScreens: View {
    let name: String
    let model: AppModel

    var body: some View {
        Group {
            switch name {
            case "paywall":
                ZStack {
                    MorningStage(depth: 1)
                    PaywallView(model: model)
                }
            case "microphone":
                ZStack {
                    MorningStage(depth: 1)
                    MicrophonePrimerView {}
                }
            case "reminders":
                ZStack {
                    MorningStage(depth: 1)
                    RemindersPrimerView(practiceTitle: "Tell me about yourself") {}
                }
            case "setup":
                ZStack {
                    MorningStage(depth: 1)
                    SetupCompleteView(model: model) {}
                }
            case "existing":
                ZStack {
                    MorningStage(depth: 1)
                    ExistingAccountView {}
                }
            case "briefing":
                BriefingView(practice: PracticeCatalog.definition("interview_tell_me_about_yourself")!, onBack: {}, onStart: { _ in })
            case "settings":
                SettingsView(model: model)
            case "room", "debrief", "assessing", "recovery", "retry":
                PracticeSessionView(session: reviewSession, onClose: {})
            case "library":
                LibraryView { _ in }
            case "profile":
                ProfileView(model: model)
            case "signin":
                ZStack {
                    MorningStage(depth: 0.3)
                    SignInView(model: model) {}
                }
            case "welcome":
                ZStack {
                    MorningStage(depth: 0)
                    WelcomeView(onGetStarted: {}, onSignIn: {})
                }
            default:
                MainShellView(model: model, onStart: { _ in })
            }
        }
        .onAppear { model.loadReviewFixture() }
    }
}

extension ReviewScreens {
    var reviewSession: PracticeSession {
        let practice = PracticeCatalog.definition("interview_tell_me_about_yourself")!
        let setup = PracticeSetup(practice: practice, pressure: .realistic, persona: .female)
        let session = PracticeSession(setup: setup, language: "en", userID: UUID(), onFinished: {})
        let context = PracticeContext.new(for: setup, language: "en")
        let transcript = [
            TranscriptLine(id: "coach-1", role: .coach, text: "Tell me a little about yourself."),
            TranscriptLine(id: "user-1", role: .user, text: "I'm a product designer. Most recently I led the redesign of our onboarding at Acme, which cut drop-off by a third."),
            TranscriptLine(id: "coach-2", role: .coach, text: "What drew you to this role?"),
            TranscriptLine(id: "user-2", role: .user, text: "Um, I guess I like the product, and, you know, the team seems great."),
        ]
        switch name {
        case "room": session.loadReviewStage(.live)
        case "assessing": session.loadReviewStage(.assessing)
        case "recovery": session.loadReviewStage(.recovery(PracticeDraft(context: context, transcript: transcript)))
        case "retry":
            var retryContext = context
            retryContext.retry = RetryCheckpoint(
                parentAttemptId: UUID(), prompt: "What drew you to this role?", context: [],
                criterionId: practice.criteria[1].id,
                previous: CriterionResult(id: practice.criteria[1].id, level: 1, note: "", evidence: [.init(turnId: "user-2", quote: "I like the product")])
            )
            let retryTranscript = [
                TranscriptLine(id: "coach-r1", role: .coach, text: "What drew you to this role?"),
                TranscriptLine(id: "user-r1", role: .user, text: "Your onboarding loses people at the same step ours did — and I've fixed that once already."),
            ]
            let assessment = PracticeAssessment(
                summary: "This time your reason was specific and tied to your own result.",
                criteria: [CriterionResult(id: practice.criteria[1].id, level: 2, note: "You named something specific about their product.", evidence: [.init(turnId: "user-r1", quote: "Your onboarding loses people at the same step ours did")])],
                adjustment: "Keep the link, then stop — the silence after a strong line is yours.",
                targetCriterionId: practice.criteria[1].id,
                limitations: []
            )
            session.loadReviewStage(.report(PracticeReport(id: UUID(), transcript: retryTranscript, analysis: .init(score: 67, summary: nil, practice: assessment, practiceContext: retryContext))))
        default:
            let assessment = PracticeAssessment(
                summary: "You opened with a clear, concrete story — then the second answer lost its shape.",
                criteria: [
                    CriterionResult(id: practice.criteria[0].id, level: 2, note: "You led with who you are now and one real result.", evidence: [.init(turnId: "user-1", quote: "Most recently I led the redesign of our onboarding at Acme, which cut drop-off by a third.")]),
                    CriterionResult(id: practice.criteria[1].id, level: 1, note: "Your reason for the role was there, but vague.", evidence: [.init(turnId: "user-2", quote: "I like the product")]),
                    CriterionResult(id: practice.criteria[2].id, level: 0, note: "You didn't connect your strength to what they need yet.", evidence: []),
                ],
                adjustment: "When they ask why this role, name one specific thing about their product and link it to the result you just described.",
                targetCriterionId: practice.criteria[1].id,
                limitations: []
            )
            let report = PracticeReport(id: UUID(), transcript: transcript, analysis: .init(score: 50, summary: nil, practice: assessment, practiceContext: context))
            session.loadReviewStage(.report(report))
        }
        return session
    }
}

extension AppModel {
    func loadReviewFixture() {
        var answers = OnboardingAnswers.reviewFixture(before: .account)
        answers.language = "en"
        setReviewProfile(answers.profile())
        if LaunchFlags.has("-review-plans") { subscriptions.useReviewPlans() }
    }
}

extension Subscriptions {
    /// Placeholder plans for layout review only — real prices always come
    /// from the App Store through RevenueCat.
    func useReviewPlans() {
        setReviewPlans([
            Plan(id: "annual", isAnnual: true, name: "Yearly", priceString: "$59.99", periodWord: "year",
                 perMonthString: "$5.00", trialDays: 7, priceValue: 59.99),
            Plan(id: "monthly", isAnnual: false, name: "Monthly", priceString: "$9.99", periodWord: "month",
                 perMonthString: nil, trialDays: 0, priceValue: 9.99),
        ])
    }
}
#endif
