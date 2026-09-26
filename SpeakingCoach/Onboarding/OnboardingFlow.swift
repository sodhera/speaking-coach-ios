import SwiftUI

/// The sign-up flow. Its arc is the argument:
///
/// name → **category** (the door they came in through) →
/// situation → **pain** (the deck) → **support** → **cost**
/// → **reframe** (a practice problem, not a talent problem) → **outcome** →
/// **promise** → **demo** (a tap-through example) → **plan** →
/// **commit** → account.
///
/// Structure mirrors SleepBlock's questionnaire: one primary button per step
/// and one gesture (the fingerprint hold); asks alternate with reveals; steps
/// fade, they never slide or overlap.
struct OnboardingFlow: View {
    let model: AppModel
    /// False for quick setup after a sign-in: the account already exists.
    let includesAccount: Bool
    var onExit: (() -> Void)?
    var onProgress: ((Double) -> Void)?

    enum Step: String, Codable, CaseIterable {
        case name, category, moment, timing, readiness, deck, mirror, cost, reframe, outcome, promise, demo, plan, commit, account
    }

    @State private var answers = OnboardingAnswers()
    @State private var step: Step = .name
    @State private var deckIndex = 0
    @State private var contentVisible = true
    @State private var stepSettled = false
    @State private var movingForward = true
    @State private var revealReady = false
    @State private var draftRestored = false
    @State private var draftsEnabled = true

    private static let draftKey = "sc.onboardingDraft.v1"
    private static let fadeOut: TimeInterval = 0.15
    private static let fadeIn: TimeInterval = 0.30

    private var steps: [Step] {
        Step.allCases.filter { step in
            switch step {
            case .account: return includesAccount
            // A door with one situation (Presentations) has already
            // answered the second question.
            case .moment: return (answers.category?.moments.count ?? 2) > 1
            // Speaking better in general has no date to ask about.
            case .timing: return answers.moment?.isGeneral != true
            // No "That's me" and no "Sometimes": nothing has cost them anything.
            case .cost: return answers.reportsPain || answers.statements.count < PainStatement.allCases.count
            default: return true
            }
        }
    }

    private var currentIndex: Int { steps.firstIndex(of: step) ?? 0 }
    private var progress: Double { Double(currentIndex + 1) / Double(steps.count) }
    private var moment: SpeakingMoment { answers.moment ?? .interview }
    private var trimmedName: String { answers.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var firstName: String { trimmedName.split(separator: " ").first.map(String.init) ?? trimmedName }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.md)

            if step == .account {
                // The account step owns its full vertical layout.
                AuthMethodsView(model: model, intent: .signUp, onSwipeBack: { goBack() })
                    .padding(.horizontal, Space.xxl)
                    .opacity(contentVisible ? 1 : 0)
            } else {
                // Scrolls only when a step outgrows a small screen (seven
                // answers on an iPhone SE); otherwise it sits still and
                // centres exactly as `QuestionLayout` lays it out.
                GeometryReader { viewport in
                    ScrollView {
                        currentStep
                            .frame(maxWidth: .infinity, minHeight: viewport.size.height - Space.xxxl, alignment: .top)
                            .padding(.horizontal, Space.xxl)
                            .padding(.top, Space.xxxl)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                }
                // `.identity`, not a cross-fade: `contentVisible` owns the
                // fade so two steps are never on screen at once.
                .transition(.identity)
                .id(step)
                .opacity(contentVisible ? 1 : 0)

                actions
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.lg)
            }
        }
        // Chrome only — the progress bar and chevron glide; content fades.
        .animation(.easeInOut(duration: 0.34), value: step)
        .swipeBack {
            guard step != .account, canGoBack else { return }
            Haptics.soft()
            goBack()
        }
        .onAppear {
            restoreDraft()
            onProgress?(depth(for: step))
            Analytics.enter(pageID(step), step: currentIndex)
        }
        .task(id: step) {
            // The settle only applies going forward: coming back to an
            // answered step, the question isn't new and the wait is friction.
            guard movingForward else { stepSettled = true; return }
            stepSettled = false
            try? await Task.sleep(for: Motion.settle)
            guard !Task.isCancelled else { return }
            stepSettled = true
        }
        .onChange(of: step) { _, next in
            onProgress?(depth(for: next))
            Analytics.enter(pageID(next), step: currentIndex)
            saveDraft()
        }
        .onChange(of: answers) { _, _ in saveDraft() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.lg) {
            GlassBackButton { goBack() }
                .opacity(canGoBack ? 1 : 0)
                .disabled(!canGoBack)
            ProgressBar(fraction: progress)
            // The chevron's hidden twin keeps the bar centred whatever size
            // the system draws the glass button at — and the bloom rides its
            // slot, so the flow stays branded without adding any width.
            GlassBackButton {}
                .hidden()
                .accessibilityHidden(true)
                .overlay { BrandMark(size: 30) }
        }
        .animation(.easeInOut(duration: 0.28), value: canGoBack)
    }

    private var canGoBack: Bool { currentIndex > 0 || onExit != nil }

    // MARK: Steps

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case .name:
            QuestionLayout(title: String(localized: "What should we call you?", bundle: AppLanguage.bundle)) {
                NameField(name: $answers.name, onSubmit: advance)
            }

        case .category:
            QuestionLayout(
                title: trimmedName.isEmpty
                    ? String(localized: "What are you practicing for?", bundle: AppLanguage.bundle)
                    : String(localized: "\(firstName), what are you practicing for?", bundle: AppLanguage.bundle, comment: "Slot: the user's first name."),
                subtitle: String(localized: "Pick the one that matters most.", bundle: AppLanguage.bundle)
            ) {
                GlassGroup(spacing: Space.md) {
                    VStack(spacing: Space.md) {
                        ForEach(SpeakingCategory.allCases) { category in
                            OptionRow(icon: category.icon, title: category.title, isSelected: answers.category == category) {
                                chooseCategory(category)
                            }
                        }
                    }
                }
            }

        case .moment:
            QuestionLayout(
                title: answers.category == .everyday ? String(localized: "What would help most?", bundle: AppLanguage.bundle) : String(localized: "What's coming up?", bundle: AppLanguage.bundle),
                subtitle: String(localized: "Pick the one that matters most.", bundle: AppLanguage.bundle)
            ) {
                options(answers.category?.moments ?? [], icon: \.icon, title: \.title, isSelected: { answers.moment == $0 }) {
                    chooseMoment($0)
                }
            }

        case .timing:
            QuestionLayout(title: moment.timingQuestion) {
                options(MomentTiming.allCases, icon: \.icon, title: \.title, isSelected: { answers.timing == $0 }) {
                    if let old = answers.timing, old != $0 {
                        trackChoice("timing", old.rawValue, selected: false)
                    }
                    answers.timing = $0
                    trackChoice("timing", $0.rawValue, selected: true)
                }
            }

        case .readiness:
            QuestionLayout(title: moment.readinessQuestion) {
                CoachSlider(
                    value: $answers.readiness,
                    touched: $answers.readinessTouched,
                    range: 0...10,
                    lowLabel: String(localized: "Not at all", bundle: AppLanguage.bundle),
                    highLabel: String(localized: "Completely", bundle: AppLanguage.bundle),
                    caption: String(localized: "Be honest.", bundle: AppLanguage.bundle),
                    unit: String(localized: "out of 10", bundle: AppLanguage.bundle),
                    accessibilityName: String(localized: "Readiness", bundle: AppLanguage.bundle)
                )
            }

        case .deck:
            QuestionLayout(title: String(localized: "Does this sound like you?", bundle: AppLanguage.bundle), readout: String(localized: "\(deckIndex + 1) of \(PainStatement.allCases.count)", bundle: AppLanguage.bundle, comment: "Progress through the statements, e.g. 2 of 6.")) {
                DeckInstrument(
                    index: deckIndex,
                    selected: answers.statements[PainStatement.allCases[deckIndex]],
                    onAnswer: answerDeck
                )
            }

        case .mirror:
            QuestionLayout(title: trimmedName.isEmpty
                ? String(localized: "We'll work through this together.", bundle: AppLanguage.bundle)
                : String(localized: "\(firstName), we'll work through this together.", bundle: AppLanguage.bundle, comment: "Slot: the user's first name.")) {
                MirrorInstrument(pattern: answers.pattern, ready: $revealReady)
            }

        case .cost:
            QuestionLayout(title: String(localized: "What has it cost you so far?", bundle: AppLanguage.bundle), subtitle: String(localized: "Choose any that fit.", bundle: AppLanguage.bundle)) {
                options(SpeakingCost.allCases, icon: \.icon, title: \.title, isSelected: { answers.costs.contains($0) }) { choice in
                    let previous = answers.costs
                    if choice == .nothingYet {
                        answers.costs = answers.costs.contains(.nothingYet) ? [] : [.nothingYet]
                    } else {
                        answers.costs.remove(.nothingYet)
                        answers.costs.formSymmetricDifference([choice])
                    }
                    for value in SpeakingCost.allCases where previous.contains(value) != answers.costs.contains(value) {
                        trackChoice("cost", value.rawValue, selected: answers.costs.contains(value))
                    }
                }
            }

        case .reframe:
            // The punchline lands last: the typewriter retires every earlier
            // line, so whatever is typed last is what stays in front.
            NarrativePage(lines: [
                String(localized: "Most people never say it out loud until the moment it counts.", bundle: AppLanguage.bundle),
                String(localized: "So it isn't a talent problem.", bundle: AppLanguage.bundle),
                String(localized: "It's a practice problem.", bundle: AppLanguage.bundle),
            ], ready: $revealReady)

        case .outcome:
            QuestionLayout(title: moment.outcomeQuestion, subtitle: String(localized: "Choose any that fit.", bundle: AppLanguage.bundle)) {
                options(moment.outcomeOptions, icon: \.icon, title: \.title, isSelected: { answers.outcomes.contains($0) }) {
                    let wasSelected = answers.outcomes.contains($0)
                    answers.outcomes.formSymmetricDifference([$0])
                    trackChoice("outcome", $0.rawValue, selected: !wasSelected)
                }
            }

        case .promise:
            // Their moment and their outcomes, handed back as a promise. The
            // last line is the one that stays in front.
            NarrativePage(lines: [
                trimmedName.isEmpty
                    ? String(localized: "Here's our promise.", bundle: AppLanguage.bundle)
                    : String(localized: "\(firstName), here's our promise.", bundle: AppLanguage.bundle, comment: "Slot: the user's first name."),
                String(localized: "Practice it with us first,", bundle: AppLanguage.bundle, comment: "Second line of the promise; the third line continues it: 'and you'll walk into your interview calm.'"),
                moment.promise(outcomes: answers.outcomes),
            ], ready: $revealReady)

        case .demo:
            QuestionLayout(title: String(localized: "See how practice works.", bundle: AppLanguage.bundle)) {
                DemoInstrument(script: DemoScript.for(moment), ready: $revealReady)
            }

        case .plan:
            QuestionLayout(title: planHeadline) {
                PlanInstrument(answers: answers, ready: $revealReady)
            }

        case .commit:
            // The fingerprint *is* this step, so it lives in the content
            // region, not the bottom slot. No subtitle: this is the one step
            // where the user is asked to answer rather than to read.
            QuestionLayout(title: commitTitle) {
                CommitmentHoldButton {
                    Analytics.action(pageID(.commit), step: currentIndex)
                    model.commitOnboarding(answers)
                    if includesAccount { advance() }
                }
            }

        case .account:
            EmptyView()
        }
    }

    private func options<Option: Identifiable>(
        _ items: [Option],
        icon: @escaping (Option) -> String,
        title: @escaping (Option) -> String,
        isSelected: @escaping (Option) -> Bool,
        toggle: @escaping (Option) -> Void
    ) -> some View {
        GlassGroup(spacing: Space.md) {
            VStack(spacing: Space.md) {
                ForEach(items) { item in
                    OptionRow(icon: icon(item), title: title(item), isSelected: isSelected(item)) { toggle(item) }
                }
            }
        }
    }

    private var planHeadline: String {
        moment.arrival(answers.timing ?? .noDate)
    }

    private var commitTitle: String {
        moment.commitQuestion(name: firstName)
    }

    // MARK: Actions

    /// One button per step. Reveal steps keep theirs **absent** until the
    /// reveal lands (there's nothing to press while it's still arriving, and
    /// a greyed button only invites pressing it); its space stays reserved so
    /// nothing jumps. Question steps keep theirs visible but dimmed through
    /// the 900ms settle.
    @ViewBuilder
    private var actions: some View {
        switch step {
        case .commit, .deck:
            // The hold is the commit step's action; the deck's rows are its own.
            Color.clear.frame(height: 58)
        case .mirror, .reframe, .demo:
            revealGatedButton(String(localized: "Continue", bundle: AppLanguage.bundle))
        case .promise:
            revealGatedButton(String(localized: "Show me how", bundle: AppLanguage.bundle))
        case .plan:
            revealGatedButton(String(localized: "Commit to it", bundle: AppLanguage.bundle))
        default:
            PrimaryButton(title: String(localized: "Continue", bundle: AppLanguage.bundle), action: advance)
                .disabled(!(isStepValid && stepSettled))
        }
    }

    private func revealGatedButton(_ title: String) -> some View {
        PrimaryButton(title: title, action: advance)
            .disabled(!revealReady)
            .opacity(revealReady ? 1 : 0)
            .animation(.easeInOut(duration: 0.35), value: revealReady)
    }

    private var isStepValid: Bool {
        switch step {
        case .name: !trimmedName.isEmpty
        case .category: answers.category != nil
        case .moment: answers.moment.map { answers.category?.moments.contains($0) == true } ?? false
        case .timing: answers.timing != nil
        case .readiness: answers.readinessTouched
        case .cost: !answers.costs.isEmpty
        case .outcome: !answers.outcomes.isEmpty
        case .mirror, .reframe, .promise, .demo, .plan: revealReady
        default: true
        }
    }

    // MARK: Choosing

    private func chooseCategory(_ category: SpeakingCategory) {
        if let old = answers.category, old != category {
            trackChoice("category", old.rawValue, selected: false)
        }
        trackChoice("category", category.rawValue, selected: true)
        answers.category = category
        if category.moments.count == 1 {
            chooseMoment(category.moments[0])
        } else if let moment = answers.moment, !category.moments.contains(moment) {
            trackChoice("moment", moment.rawValue, selected: false)
            answers.moment = nil
        }
    }

    private func chooseMoment(_ moment: SpeakingMoment) {
        let wasGeneral = answers.moment?.isGeneral == true
        if let old = answers.moment, old != moment {
            trackChoice("moment", old.rawValue, selected: false)
        }
        trackChoice("moment", moment.rawValue, selected: true)
        answers.moment = moment
        // No event, so no date: the timing step is skipped and "no date" is
        // recorded for them. Switching back to a specific moment clears
        // that, so they answer it themselves.
        if moment.isGeneral {
            if let old = answers.timing, old != .noDate {
                trackChoice("timing", old.rawValue, selected: false)
            }
            if answers.timing != .noDate {
                trackChoice("timing", MomentTiming.noDate.rawValue, selected: true)
            }
            answers.timing = .noDate
        } else if wasGeneral {
            trackChoice("timing", MomentTiming.noDate.rawValue, selected: false)
            answers.timing = nil
        }
        // Outcomes are offered per moment; drop any the new one doesn't offer.
        let previousOutcomes = answers.outcomes
        answers.outcomes.formIntersection(moment.outcomeOptions)
        for outcome in SpeakingOutcome.allCases where previousOutcomes.contains(outcome) && !answers.outcomes.contains(outcome) {
            trackChoice("outcome", outcome.rawValue, selected: false)
        }
    }

    private func answerDeck(_ agreement: Agreement) {
        let statement = PainStatement.allCases[deckIndex]
        trackChoice("challenge_rating", agreement.rawValue, context: statement.rawValue)
        let hadPain = answers.reportsPain
        let previousCosts = answers.costs
        answers.statements[statement] = agreement
        // No pain reported means the cost question is skipped and "nothing
        // yet" recorded for them — cleared again if pain appears, so they
        // answer it themselves.
        if answers.statements.count == PainStatement.allCases.count {
            if !answers.reportsPain {
                answers.costs = [.nothingYet]
            } else if !hadPain, answers.costs == [.nothingYet] {
                answers.costs = []
            }
        }
        for cost in SpeakingCost.allCases where previousCosts.contains(cost) != answers.costs.contains(cost) {
            trackChoice("cost", cost.rawValue, selected: answers.costs.contains(cost))
        }
        let answeredIndex = deckIndex
        Task { @MainActor in
            // Long enough to see the selection land, short enough to keep pace.
            try? await Task.sleep(for: .milliseconds(320))
            guard step == .deck, deckIndex == answeredIndex else { return }
            if deckIndex < PainStatement.allCases.count - 1 {
                deckIndex += 1
            } else {
                advance()
            }
        }
    }

    // No haptic here: the button already knocks, and this also runs from the
    // name field's return key.
    private func advance() {
        guard isStepValid || step == .deck || step == .commit else { return }
        recordCurrentAnswer()
        Analytics.action(pageID(step), step: currentIndex)
        let nextIndex = currentIndex + 1
        guard nextIndex < steps.count else { return }
        let next = steps[nextIndex]
        if step == .name {
            // Let the keyboard start dismissing before the fade so the two
            // animations don't fight.
            Keyboard.dismiss()
            Task { @MainActor in
                await Task.yield()
                setStep(next, forward: true)
            }
            return
        }
        setStep(next, forward: true)
    }

    /// Captures the final bounded response on each question page. The name
    /// and narrative pages are omitted.
    private func recordCurrentAnswer() {
        func record(_ field: String, _ value: String, selected: Bool? = nil) {
            Analytics.onboardingChoice(
                page: pageID(step), field: field, value: value,
                selected: selected, event: "onboarding_answer", step: currentIndex
            )
        }
        switch step {
        case .category:
            if let category = answers.category { record("category", category.rawValue, selected: true) }
            if let moment = answers.moment { record("moment", moment.rawValue, selected: true) }
        case .moment:
            if let moment = answers.moment { record("moment", moment.rawValue, selected: true) }
        case .timing:
            if let timing = answers.timing { record("timing", timing.rawValue, selected: true) }
        case .readiness where answers.readinessTouched:
            record("readiness", String(min(max(answers.readiness, 0), 10)))
        case .deck:
            for statement in PainStatement.allCases {
                if let answer = answers.statements[statement] {
                    Analytics.onboardingChoice(
                        page: pageID(step), field: "challenge_rating", value: answer.rawValue,
                        context: statement.rawValue, event: "onboarding_answer", step: currentIndex
                    )
                }
            }
        case .cost:
            for cost in SpeakingCost.allCases where answers.costs.contains(cost) {
                record("cost", cost.rawValue, selected: true)
            }
        case .outcome:
            for outcome in SpeakingOutcome.allCases where answers.outcomes.contains(outcome) {
                record("outcome", outcome.rawValue, selected: true)
            }
        default:
            break
        }
    }

    private func trackChoice(_ field: String, _ value: String, selected: Bool? = nil, context: String? = nil) {
        Analytics.onboardingChoice(
            page: pageID(step), field: field, value: value,
            selected: selected, context: context, step: currentIndex
        )
    }

    private func goBack() {
        if step == .deck, deckIndex > 0 {
            withAnimation(.easeInOut(duration: 0.3)) { deckIndex -= 1 }
            return
        }
        let previousIndex = currentIndex - 1
        Keyboard.dismiss()
        guard previousIndex >= 0 else {
            onExit?()
            return
        }
        // From the account step, back returns to the plan rather than
        // re-offering a hold that has already been made.
        let target = step == .account ? .plan : steps[previousIndex]
        if target == .deck { deckIndex = PainStatement.allCases.count - 1 }
        setStep(target, forward: false)
    }

    /// Steps fade out, swap behind a blank frame, then fade in. The button
    /// closes the moment the fade *starts* — otherwise it sits lit over an
    /// empty screen, and a second tap would advance the step on its way out.
    private func setStep(_ next: Step, forward: Bool) {
        movingForward = forward
        stepSettled = false
        withAnimation(.easeIn(duration: Self.fadeOut)) { contentVisible = false }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.fadeOut))
            withAnimation(.easeInOut(duration: 0.34)) { step = next }
            revealReady = false
            withAnimation(.easeOut(duration: Self.fadeIn)) { contentVisible = true }
        }
    }

    /// The sun rises with progress and peaks on the commitment.
    private func depth(for step: Step) -> Double {
        guard let position = steps.firstIndex(of: step), let commit = steps.firstIndex(of: .commit) else { return 1 }
        return min(Double(position) / Double(commit), 1)
    }

    private func pageID(_ step: Step) -> String { "ob_\(step.rawValue.lowercased())" }

    // MARK: Draft

    private struct Draft: Codable {
        var answers: OnboardingAnswers
        var step: Step
    }

    /// Cleared by the app model once the answers are safely on an account —
    /// not at the commit, so quitting on the account step loses nothing.
    static func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
    }

    static var hasDraft: Bool { UserDefaults.standard.data(forKey: draftKey) != nil }

    private func saveDraft() {
        guard draftRestored, draftsEnabled,
              let data = try? JSONEncoder().encode(Draft(answers: answers, step: step)) else { return }
        UserDefaults.standard.set(data, forKey: Self.draftKey)
    }

    private func restoreDraft() {
        guard !draftRestored else { return }
        defer { draftRestored = true }
        #if DEBUG
        if let review = LaunchFlags.value("-review-onboarding-step"), let target = Step(rawValue: review) {
            draftsEnabled = false
            answers = .reviewFixture(before: target)
            step = target
            return
        }
        #endif
        guard let data = UserDefaults.standard.data(forKey: Self.draftKey),
              let draft = try? JSONDecoder().decode(Draft.self, from: data) else { return }
        answers = draft.answers
        var resume = steps.contains(draft.step) ? draft.step : .name
        // Never resume onto a commitment already made or the account step —
        // land on the plan, so the user re-reads what they're committing to.
        if resume == .commit || resume == .account { resume = .plan }
        // Never resume past a missing required answer, or later screens would
        // be built from defaults the user never chose.
        func index(_ s: Step) -> Int { steps.firstIndex(of: s) ?? 0 }
        let required: [(Step, Bool)] = [
            (.name, !trimmedName.isEmpty), (.category, answers.category != nil), (.moment, answers.moment != nil), (.timing, answers.timing != nil),
            (.readiness, answers.readinessTouched), (.deck, answers.statements.count == PainStatement.allCases.count),
            (.cost, !answers.costs.isEmpty), (.outcome, !answers.outcomes.isEmpty),
        ]
        if let missing = required.first(where: { steps.contains($0.0) && !$0.1 && index($0.0) < index(resume) }) {
            resume = missing.0
        }
        step = resume
        deckIndex = min(answers.statements.count, PainStatement.allCases.count - 1)
    }
}

#if DEBUG
extension OnboardingAnswers {
    /// Answers for every step *before* `step`, so a review route shows a
    /// step's real initial state — never pre-answering the step itself.
    static func reviewFixture(before step: OnboardingFlow.Step) -> OnboardingAnswers {
        let order = OnboardingFlow.Step.allCases
        let target = order.firstIndex(of: step) ?? 0
        func past(_ s: OnboardingFlow.Step) -> Bool { (order.firstIndex(of: s) ?? 0) < target }
        var answers = OnboardingAnswers()
        if past(.name) { answers.name = "Sulav" }
        // `-review-moment=everyday` previews the flow for a different answer.
        let moment = LaunchFlags.value("-review-moment").flatMap(SpeakingMoment.init(rawValue:)) ?? .interview
        if past(.category) { answers.category = moment.category }
        if past(.moment) || (past(.category) && moment.category.moments.count == 1) { answers.moment = moment }
        if past(.timing) { answers.timing = moment.isGeneral ? .noDate : .thisWeek }
        if past(.readiness) { answers.readiness = 4; answers.readinessTouched = true }
        if past(.deck) {
            answers.statements = [
                .wordsVanish: .yes, .blankOnTheSpot: .yes, .rambleWhenNervous: .sometimes,
                .stayQuiet: .no, .onlyInMyHead: .yes, .replayAfterwards: .sometimes,
            ]
        }
        if past(.cost) { answers.costs = [.jobOrPromotion, .selfConfidence] }
        if past(.outcome) { answers.outcomes = [.calm, .clear] }
        return answers
    }
}
#endif
