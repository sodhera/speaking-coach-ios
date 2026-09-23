#if DEBUG
import SwiftUI

/// `-review-screen=<name>` renders a screen against a fixture profile, with
/// no account or purchase needed: `welcome`, `signin`, `existing`, `paywall`,
/// `microphone`, `reminders`, `setup`, `home`, `profile`, `library`,
/// `briefing`, `settings`, `checkin`. Add `-review-plan-step=retry|finish|done`
/// to see Home (or the hand-off) partway through the first plan.
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
                    SetupCompleteView(model: model) { _ in }
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
            case "checkin":
                ZStack {
                    MorningStage(depth: 1)
                    if let plan = FirstPlan(profile: model.profile, records: model.history.records) {
                        PlanCheckInView(plan: plan) { model.completePlan(readiness: $0) }
                    }
                }
            case "custom":
                CustomSituationView(language: "en", onBack: {}, onStart: { _, _ in })
            case "room", "debrief", "assessing", "recovery", "retry", "customdebrief":
                PracticeSessionView(session: reviewSession, onClose: {})
            case "library":
                LibraryView(presentations: model.presentations, model: model) { _ in }
            case "routine":
                NavigationStack {
                    RoutineView(routine: model.routine, language: "en", onBack: {})
                }
            case "prompt":
                PromptView(routine: model.routine, source: .reminder, language: "en", onClose: {})
            case "planprogress":
                NavigationStack {
                    PreparationPlanView(model: model, onBack: {}, onPractice: { _ in })
                }
                .onAppear {
                    model.preparation.setReviewPlan(PreparationPlan(
                        programID: "interview", eventName: "Interview at Acme",
                        eventDate: Calendar.current.date(byAdding: .day, value: 5, to: .now), reminderEnabled: true,
                        createdAt: .distantPast, reflection: nil
                    ))
                }
            case "plan":
                NavigationStack {
                    PreparationPlanView(model: model, onBack: {}, onPractice: { _ in })
                }
            case "feedback":
                FeedbackView(userID: nil)
            case "presentations":
                NavigationStack {
                    PresentationsView(store: model.presentations, language: "en", onBack: {})
                }
                .onAppear { _ = model.presentations.loadReviewFixture() }
            case "deck":
                let (deck, _) = model.presentations.loadReviewFixture()
                NavigationStack {
                    DeckView(store: model.presentations, deck: deck, language: "en", onBack: {})
                }
            case "presentationreview":
                let (deck, rehearsal) = model.presentations.loadReviewFixture()
                NavigationStack {
                    RehearsalReviewView(store: model.presentations, deck: deck, rehearsalID: rehearsal.id, language: "en", isFresh: true, onBack: {})
                }
            case "rehearsalready":
                let (deck, _) = model.presentations.loadReviewFixture()
                RehearsalView(store: model.presentations, deck: deck, language: "en", onClose: {})
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
        case "customdebrief":
            let situation = CustomSituation(description: "Ask my landlord to return my deposit.", partner: "My landlord", title: "Talking to my landlord")
            let lines = [
                TranscriptLine(id: "coach-c1", role: .coach, text: "Oh, hi. Is this about the deposit again?"),
                TranscriptLine(id: "user-c1", role: .user, text: "Yeah, um, sorry to bother you, I was just wondering if maybe the deposit could come back soon?"),
            ]
            let analysis = PracticeReport.Analysis(
                score: 58,
                summary: "You raised the issue, but the apology and the maybe made it easy to put you off.",
                improvements: ["Lead with the ask, not an apology.", "Name the amount and a date.", "If they deflect, calmly repeat the ask once."],
                subscores: [
                    Subscore(label: "Clarity", score: 64, note: "The request was there, but wrapped in hedges."),
                    Subscore(label: "Confidence", score: 46, note: "“Sorry to bother you” set a weak frame."),
                    Subscore(label: "Assertiveness", score: 41, note: "You asked if it *could* come back, not when it will."),
                    Subscore(label: "Warmth", score: 78, note: "Friendly and respectful throughout."),
                ],
                rewrites: [Rewrite(original: "Sorry to bother you, I was just wondering if maybe the deposit could come back soon?", better: "I'm calling about my £900 deposit. I'd like it returned by Friday — can you confirm that?")],
                custom: situation
            )
            session.loadReviewStage(.report(PracticeReport(id: UUID(), transcript: lines, analysis: analysis)))
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
        var profile = answers.profile()
        let step = LaunchFlags.value("-review-plan-step")
        if step == "done" {
            profile.planReadiness = 7
            profile.planCompletedAt = .now
        }
        setReviewProfile(profile)
        history.setReviewRecords(Self.reviewRecords(for: step, practiceID: profile.moment?.firstPracticeID))
        if LaunchFlags.has("-review-plans") { subscriptions.useReviewPlans() }
    }

    /// A rehearsal of the plan's practice, then its retry — as far as the
    /// reviewed step needs.
    private static func reviewRecords(for step: String?, practiceID: String?) -> [PracticeRecord] {
        guard let step, step != "rehearse" else { return [] }
        let first = PracticeRecord(id: UUID(), activityID: practiceID, title: "First", date: .now.addingTimeInterval(-3600), score: nil, parentID: nil)
        guard step != "retry" else { return [first] }
        let retry = PracticeRecord(id: UUID(), activityID: practiceID, title: "Retry", date: .now, score: nil, parentID: first.id)
        return [retry, first]
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

#if DEBUG
extension PresentationStore {
    /// A three-slide deck with one rehearsal, for reviewing the screens.
    func loadReviewFixture() -> (PresentationDeck, PresentationRehearsal) {
        if let deck = decks.first, let rehearsal = rehearsals[deck.id]?.first { return (deck, rehearsal) }
        let slides = [
            ("Q3 Growth Plan", "Where we are, and what we need"),
            ("Retention is the lever", "Churn fell 18% after onboarding changes"),
            ("The ask", "Two engineers for one quarter"),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 960, height: 540)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for (title, subtitle) in slides {
                context.beginPage()
                UIColor(red: 0.13, green: 0.16, blue: 0.24, alpha: 1).setFill()
                context.fill(bounds)
                (title as NSString).draw(at: CGPoint(x: 64, y: 190), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 54), .foregroundColor: UIColor.white])
                (subtitle as NSString).draw(at: CGPoint(x: 64, y: 270), withAttributes: [.font: UIFont.systemFont(ofSize: 28), .foregroundColor: UIColor(white: 0.8, alpha: 1)])
            }
        }
        var deck = try! importPDF(data, fileName: "Q3 Growth Plan.pdf")
        deck.brief = PresentationBrief(audience: "the leadership team", purpose: "approve two engineers for Q3", instructions: "", questionStyle: .curious)
        update(deck)
        let questions = [
            AudienceQuestion(id: "q1", question: "What happens to retention if we don't get the two engineers?", reason: "Tests the cost of inaction.", slideIndex: 2),
            AudienceQuestion(id: "q2", question: "How confident are you that the 18% drop came from onboarding and not seasonality?", reason: "Tests the evidence.", slideIndex: 1),
            AudienceQuestion(id: "q3", question: "What would you cut if we could only give you one engineer?", reason: "Tests priorities.", slideIndex: nil),
        ]
        let rehearsal = PresentationRehearsal(
            id: UUID(), deckID: deck.id, startedAt: .now.addingTimeInterval(-600), durationMs: 262_000, audioFile: "missing.m4a",
            transcript: String(repeating: "So the reason retention matters this quarter is that every point we keep is worth more than a new signup. ", count: 30),
            slideEvents: [SlideEvent(slideIndex: 0, atMs: 0), SlideEvent(slideIndex: 1, atMs: 60_000), SlideEvent(slideIndex: 2, atMs: 180_000)],
            questions: questions,
            answers: [QuestionAnswer(questionId: "q1", transcript: "Um, I think it would probably go back up, because the onboarding work would stall and we'd lose what we gained.", feedback: "Lead with the number: say how much churn you'd expect to return, then name the one project that would stall.")]
        )
        save(rehearsal)
        return (deck, rehearsal)
    }
}
#endif
