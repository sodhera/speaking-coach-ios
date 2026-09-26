#if DEBUG
import SwiftUI

/// One continuous, local-only walk through for recording Zara's sample talk.
/// It never authenticates, records audio, or calls the coaching server.
struct ZaraDemoFlow: View {
    let model: AppModel
    @State private var step: Step = .welcome

    private enum Step: Equatable { case welcome, account, home }

    var body: some View {
        Group {
            switch step {
            case .welcome:
                ZStack {
                    MorningStage(depth: 0)
                    WelcomeView(onGetStarted: { step = .account }, onSignIn: { step = .account })
                }
            case .account:
                ZStack {
                    MorningStage(depth: 0)
                    VStack(spacing: Space.lg) {
                        Spacer()
                        BrandMark(size: 128)
                        Text("Zara's demo account")
                            .font(Typeface.hero(30))
                            .foregroundStyle(Palette.ink)
                        Text("A local sample for walking through a presentation.")
                            .font(Typeface.body(16))
                            .foregroundStyle(Palette.dim)
                            .multilineTextAlignment(.center)
                        Spacer()
                        PrimaryButton(title: "Continue as Zara") { step = .home }
                    }
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.xxl)
                }
            case .home:
                MainShellView(model: model, onStart: { _ in })
            }
        }
        .statusBarScrim()
        .environment(\.stageStyle, step == .home ? .flat : .morning)
        .onAppear {
            model.setZaraDemoIdentity()
            let deck = model.presentations.loadZaraDemoDeck()
            var emptyDeck = deck
            emptyDeck.brief = PresentationBrief()
            model.presentations.update(emptyDeck)
        }
    }
}

/// `-review-screen=<name>` renders a screen against a fixture profile, with
/// no account or purchase needed: `welcome`, `signin`, `existing`, `paywall`,
/// `attribution`, `microphone`, `reminders`, `setup`, `home`, `profile`, `progress`,
/// `library`, `briefing`, `settings`, `checkin`. Add `-review-plan-step=retry|finish|done`
/// to see Home (or the hand-off) partway through the first plan; `progress`
/// brings its own four weeks of practice.
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
            case "attribution":
                ZStack {
                    MorningStage(depth: 1)
                    AttributionView { _ in }
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
                CustomSituationView(onBack: {}, onStart: { _, _ in })
            case "room", "connecting", "debrief", "assessing", "recovery", "retry", "customdebrief":
                PracticeSessionView(session: reviewSession, onClose: {})
            case "routine":
                NavigationStack {
                    RoutineView(routine: model.routine, onBack: {})
                }
            case "prompt":
                PromptView(routine: model.routine, source: .reminder, onClose: {})
            case "planprogress":
                NavigationStack {
                    PreparationPlanView(model: model, onBack: {}, onPractice: { _ in })
                }
                .onAppear {
                    model.preparation.setReviewPlan(PreparationPlan(
                        programID: "interview", eventName: "My interview on Friday",
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
                    PresentationsView(store: model.presentations, onBack: {})
                }
                .onAppear { _ = model.presentations.loadReviewFixture() }
            case "deck":
                let (deck, _) = model.presentations.loadReviewFixture()
                NavigationStack {
                    DeckView(store: model.presentations, deck: deck, onBack: {})
                }
            case "presentationreview":
                let (deck, rehearsal) = model.presentations.loadReviewFixture()
                NavigationStack {
                    RehearsalReviewView(store: model.presentations, deck: deck, rehearsalID: rehearsal.id, isFresh: true, onBack: {})
                }
            case "rehearsalready":
                let (deck, _) = model.presentations.loadReviewFixture()
                RehearsalView(store: model.presentations, deck: deck, onClose: {})
            case "presentationrecording":
                let (deck, _) = model.presentations.loadReviewFixture()
                RehearsalView(store: model.presentations, deck: deck, onClose: {}, demoRecording: true)
            case "progress", "profile":
                ProfileView(model: model)
            case "welcome":
                ZStack {
                    MorningStage(depth: 0)
                    WelcomeView(onGetStarted: {}, onSignIn: {})
                }
            default:
                MainShellView(model: model, onStart: { _ in })
            }
        }
        // RootView's routed screens carry this; match what users see.
        .statusBarScrim()
        // Onboarding-side screens keep the sunrise; the app's are flat.
        .environment(\.stageStyle, LaunchFlags.value("-stage") == "morning" || ["welcome", "paywall", "attribution", "microphone", "reminders", "setup", "existing"].contains(name) ? .morning : .flat)
        .onAppear { model.loadReviewFixture() }
    }
}

extension ReviewScreens {
    var reviewSession: PracticeSession {
        // The debrief mirrors a real report on the example question.
        let practice = PracticeCatalog.definition(name == "debrief" ? "interview_evidence" : "interview_tell_me_about_yourself")!
        let setup = PracticeSetup(practice: practice, pressure: .realistic, persona: .female)
        let session = PracticeSession(setup: setup, userID: UUID(), onFinished: {})
        let context = PracticeContext.new(for: setup, language: AppLanguage.code)
        let transcript = [
            TranscriptLine(id: "coach-1", role: .coach, text: "Tell me a little about yourself."),
            TranscriptLine(id: "user-1", role: .user, text: "I'm a product designer. Most recently I led the redesign of our onboarding, which cut drop-off by a third."),
            TranscriptLine(id: "coach-2", role: .coach, text: "What drew you to this role?"),
            TranscriptLine(id: "user-2", role: .user, text: "Um, I guess I like the product, and, you know, the team seems great."),
        ]
        switch name {
        case "room": session.loadReviewStage(.live)
        case "connecting": session.loadReviewStage(.preparing)
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
                rewrites: [Rewrite(original: "Sorry to bother you, I was just wondering if maybe the deposit could come back soon?", better: "I'm calling about my £900 deposit. I'd like it returned by Friday. Can you confirm that?")],
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
                TranscriptLine(id: "user-r1", role: .user, text: "Your onboarding loses people at the same step ours did, and I've fixed that once already."),
            ]
            let assessment = PracticeAssessment(
                summary: "This time your reason was specific and tied to your own result.",
                criteria: [CriterionResult(id: practice.criteria[1].id, level: 2, note: "You named something specific about their product.", evidence: [.init(turnId: "user-r1", quote: "Your onboarding loses people at the same step ours did")])],
                adjustment: "Keep the link, then stop. The silence after a strong line is yours.",
                targetCriterionId: practice.criteria[1].id,
                limitations: []
            )
            session.loadReviewStage(.report(PracticeReport(id: UUID(), transcript: retryTranscript, analysis: .init(score: 67, summary: nil, practice: assessment, practiceContext: retryContext))))
        default:
            // Mirrors a real report: one criterion clear, one partly, one
            // missing, so every level mark and both cards show.
            let lines = [
                TranscriptLine(id: "coach-e1", role: .coach, text: practice.opening),
                TranscriptLine(id: "user-e1", role: .user, text: "Uh, there's this time when I was playing football and I had to figure out how to do free kick."),
                TranscriptLine(id: "coach-e2", role: .coach, text: "Okay. What part of that was your responsibility?"),
                TranscriptLine(id: "user-e2", role: .user, text: "We practiced a lot as a team, like every day after school, and the coach showed us some videos."),
                TranscriptLine(id: "coach-e3", role: .coach, text: "And what changed because of that?"),
                TranscriptLine(id: "user-e3", role: .user, text: "It was good. Yeah, it went well."),
                TranscriptLine(id: "coach-e4", role: .coach, text: "Thanks, that's helpful."),
            ]
            let assessment = PracticeAssessment(
                summary: "You gave an example, but it does not yet clearly answer the prompt in the three parts we're checking: situation, your own action, and result.",
                criteria: [
                    CriterionResult(id: practice.criteria[0].id, level: 2, note: "You briefly set the situation by saying it was a time playing football and working on a free kick.", evidence: [.init(turnId: "user-e1", quote: "there's this time when I was playing football and I had to figure out how to do free kick")]),
                    CriterionResult(id: practice.criteria[1].id, level: 1, note: "You described what the team did, not what you did yourself.", evidence: [.init(turnId: "user-e2", quote: "We practiced a lot as a team")]),
                    CriterionResult(id: practice.criteria[2].id, level: 0, note: "You said it went well, but not what actually happened after.", evidence: []),
                ],
                adjustment: "Next time, add one sentence that says exactly what you did and one sentence that says what happened after, without using numbers.",
                targetCriterionId: practice.criteria[1].id,
                limitations: []
            )
            session.loadReviewStage(.report(PracticeReport(id: UUID(), transcript: lines, analysis: .init(score: 50, summary: nil, practice: assessment, practiceContext: context))))
        }
        return session
    }
}

extension AppModel {
    func loadReviewFixture() {
        var profile = OnboardingAnswers.reviewFixture(before: .account).profile()
        let step = LaunchFlags.value("-review-plan-step")
        if step == "done" {
            profile.planReadiness = 7
            profile.planCompletedAt = .now
        }
        setReviewProfile(profile)
        history.setReviewRecords(LaunchFlags.value("-review-screen") == "progress"
            ? Self.reviewProgressRecords()
            : Self.reviewRecords(for: step, moment: profile.moment))
        if LaunchFlags.has("-review-plans") { subscriptions.useReviewPlans() }
    }

    /// A rehearsal of the plan's practice, then its retry — as far as the
    /// reviewed step needs.
    private static func reviewRecords(for step: String?, moment: SpeakingMoment?) -> [PracticeRecord] {
        guard let step, step != "rehearse" else { return [] }
        let practiceID = moment?.firstPractice?.id
        let first = PracticeRecord(id: UUID(), activityID: practiceID, title: "First", date: .now.addingTimeInterval(-3600), score: nil, parentID: nil)
        guard step != "retry" else { return [first] }
        let retry = PracticeRecord(id: UUID(), activityID: practiceID, title: "Retry", date: .now, score: nil, parentID: first.id)
        return [retry, first]
    }

    /// Four weeks of practice for Progress: runs of days and gaps between
    /// them, retries under their rehearsals, custom scenes without a rubric,
    /// and every level. Newest first, as the history query returns them.
    private static func reviewProgressRecords() -> [PracticeRecord] {
        let calendar = Calendar.current
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now))!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        func rehearsal(_ id: String, _ date: Date, _ levels: [Int]) -> PracticeRecord {
            let practice = PracticeCatalog.definition(id)!
            let criteria = zip(practice.criteria, levels).map { CriterionLevel(id: $0.id, level: $1) }
            return PracticeRecord(id: UUID(), activityID: id, title: practice.title, date: date, score: nil, parentID: nil, criteria: criteria)
        }
        func retry(of parent: PracticeRecord, _ date: Date, criterion: Int, level: Int) -> PracticeRecord {
            let practice = PracticeCatalog.definition(parent.activityID!)!
            return PracticeRecord(
                id: UUID(), activityID: parent.activityID, title: parent.title, date: date, score: nil, parentID: parent.id,
                criteria: [CriterionLevel(id: practice.criteria[criterion].id, level: level)]
            )
        }
        func custom(_ title: String, _ date: Date) -> PracticeRecord {
            PracticeRecord(id: UUID(), activityID: nil, title: title, date: date, score: nil, parentID: nil, isCustom: true)
        }

        let evidence = rehearsal("interview_evidence", .now.addingTimeInterval(-50 * 60), [2, 1, 0])
        let intro = rehearsal("interview_tell_me_about_yourself", at(8, 9, 5), [1, 1, 0])
        return [
            retry(of: evidence, .now.addingTimeInterval(-42 * 60), criterion: 1, level: 2),
            evidence,
            rehearsal("clear_work_update", at(1, 18, 10), [2, 2, 1]),
            rehearsal("interview_tell_me_about_yourself", at(2, 8, 30), [2, 1, 1]),
            custom(CustomSituation.streetHello.title, at(6, 19, 0)),
            rehearsal("set_a_boundary", at(7, 12, 15), [1, 1, 0]),
            retry(of: intro, at(8, 9, 20), criterion: 1, level: 2),
            intro,
            rehearsal("meet_someone_new", at(9, 20, 40), [2, 1, 2]),
            rehearsal("salary_raise", at(15, 17, 45), [1, 0, 1]),
            rehearsal("disagree_in_meeting", at(16, 13, 0), [2, 1, 1]),
            rehearsal("ask_for_clarity", at(17, 10, 30), [2, 2, 2]),
            custom("My landlord", at(24, 18, 20)),
        ]
    }
}

extension Subscriptions {
    /// Placeholder plans for layout review only — real prices always come
    /// from the App Store through RevenueCat.
    func useReviewPlans() {
        setReviewPlans([
            Plan(id: "annual", isAnnual: true, name: String(localized: "Yearly", bundle: AppLanguage.bundle), priceString: "$59.99", trialDays: 7, priceValue: 59.99),
            Plan(id: "monthly", isAnnual: false, name: String(localized: "Monthly", bundle: AppLanguage.bundle), priceString: "$9.99", trialDays: 0, priceValue: 9.99),
        ])
    }
}
#endif

#if DEBUG
extension PresentationStore {
    /// Zara's psychology slides, ready for a first rehearsal in the local demo.
    func loadZaraDemoDeck() -> PresentationDeck {
        if let deck = decks.first(where: { $0.fileName == "When Nerves Show Up.pdf" }) { return deck }
        let slides = [
            ("When nerves show up", "How to present before you feel ready"),
            ("Your body is trying to help", "A prediction is not a fact; speak with nerves present"),
            ("Make the first step small", "Feet · easy exhale · first line · one kind listener"),
            ("A simple shape for a short talk", "Open with a question · explain one idea · land the takeaway"),
            ("Confidence can come later", "You can be nervous and still be clear and prepared"),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 960, height: 540)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for (index, slide) in slides.enumerated() {
                context.beginPage()
                let title = slide.0
                let subtitle = slide.1
                UIColor(red: 0.973, green: 0.953, blue: 0.918, alpha: 1).setFill()
                context.fill(bounds)
                UIColor(red: 0.89, green: 0.42, blue: 0.40, alpha: 1).setFill()
                context.cgContext.fill(CGRect(x: 58, y: 481, width: 108, height: 3))
                ("ZARA  /  PSYCHOLOGY" as NSString).draw(at: CGPoint(x: 58, y: 448), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 15),
                    .foregroundColor: UIColor(red: 0.76, green: 0.30, blue: 0.30, alpha: 1),
                ])
                let titleFont = UIFont.boldSystemFont(ofSize: index == 0 ? 50 : 42)
                (title as NSString).draw(in: CGRect(x: 58, y: 286, width: 800, height: 112), withAttributes: [
                    .font: titleFont,
                    .foregroundColor: UIColor(red: 0.15, green: 0.13, blue: 0.13, alpha: 1),
                ])
                (subtitle as NSString).draw(in: CGRect(x: 60, y: 218, width: 780, height: 78), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 24),
                    .foregroundColor: UIColor(red: 0.41, green: 0.37, blue: 0.35, alpha: 1),
                ])
                UIColor(red: 1, green: 0.988, blue: 0.969, alpha: 1).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 822, y: 78, width: 50, height: 50))
                ("\(index + 1) / \(slides.count)" as NSString).draw(at: CGPoint(x: 58, y: 46), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 13),
                    .foregroundColor: UIColor(red: 0.41, green: 0.37, blue: 0.35, alpha: 1),
                ])
            }
        }
        var deck = try! importPDF(data, fileName: "When Nerves Show Up.pdf")
        deck.brief = PresentationBrief(
            audience: "my psychology class",
            purpose: "share one way to present while nervous",
            instructions: "I rush when I feel watched; please keep questions kind.",
            questionStyle: .supportive
        )
        update(deck)
        return deck
    }

    /// Add a sample transcript and results only when the rehearsal finishes.
    func loadReviewFixture() -> (PresentationDeck, PresentationRehearsal) {
        let deck = loadZaraDemoDeck()
        if let rehearsal = rehearsals[deck.id]?.first { return (deck, rehearsal) }
        let questions = [
            AudienceQuestion(id: "q1", question: "What could you try if the nerves show up again?", reason: "Connects the idea to everyday life.", slideIndex: 1),
            AudienceQuestion(id: "q2", question: "Why might practicing the first sentence help?", reason: "Invites Zara to explain her preparation choice.", slideIndex: 2),
            AudienceQuestion(id: "q3", question: "What would you like classmates to remember?", reason: "Gives Zara a chance to land her takeaway.", slideIndex: 4),
        ]
        let rehearsal = PresentationRehearsal(
            id: UUID(), deckID: deck.id, startedAt: .now.addingTimeInterval(-600), durationMs: 21_000, audioFile: "missing.m4a",
            transcript: "I want to look at why speaking nerves show up and one small way to keep going anyway. Sometimes my heart races and I think everyone can tell. I can remind myself that a prediction is not a fact. I can feel nervous and still explain one idea. Before I begin, I will feel my feet, let my breath out, and say my first line slowly. I do not need perfect calm. I just need the next sentence.",
            slideEvents: [SlideEvent(slideIndex: 0, atMs: 0), SlideEvent(slideIndex: 1, atMs: 5_000), SlideEvent(slideIndex: 2, atMs: 10_000), SlideEvent(slideIndex: 3, atMs: 15_000), SlideEvent(slideIndex: 4, atMs: 18_000)],
            questions: questions,
            answers: [
                QuestionAnswer(questionId: "q1", transcript: "I can try putting both feet down and starting with the next sentence.", feedback: "Clear and usable. Give one example of how the first sentence could help you restart."),
                QuestionAnswer(questionId: "q2", transcript: "If I say it slowly once, I don't have to invent my opening while I'm nervous.", feedback: "Nice cause and effect. Pause after “slowly once” so the audience can take it in."),
            ]
        )
        save(rehearsal)
        return (deck, rehearsal)
    }
}
#endif
