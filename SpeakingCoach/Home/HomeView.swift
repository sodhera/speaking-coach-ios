import SwiftUI

struct MainShellView: View {
    let model: AppModel
    /// A briefing to open the moment Home appears — the hand-off's "Start
    /// my first rehearsal".
    var pendingBriefing: Binding<PracticeDefinition?> = .constant(nil)
    let onStart: (PracticeSetup) -> Void
    var onOpenReport: (PracticeReport) -> Void = { _ in }
    var onStartCustom: (CustomSituation, PracticeSetup) -> Void = { _, _ in }

    var body: some View {
        TabView {
            HomeView(model: model, pendingBriefing: pendingBriefing, onStart: onStart, onOpenReport: onOpenReport, onStartCustom: onStartCustom)
                // The brand's petals, as a template image the tab bar tints.
                .tabItem { Label("Practice", image: "TabMark") }
            ProfileView(model: model, onOpenReport: onOpenReport)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Palette.coral)
        .environment(\.stageStyle, .flat)
    }
}

/// **Practice: keep the habit, then pick something.** Three reads, top to
/// bottom, nothing hidden behind a control:
///
/// 1. **Your streak.** The number, the week as a disc per day, and whether
///    today is done. The one piece of the screen about showing up.
/// 2. **For you.** A carousel whose next card peeks in from the right: what's
///    up next (the first plan, an event plan, or the next unpracticed
///    session), a recommended scene with a hook, and, with no event plan,
///    an offer to build one. Dots under it say how many there are.
/// 3. **Situations.** Four cards, each its own page: Presentations, Work &
///    interviews, Friends & family, Custom & impromptu.
///
/// A situation dropdown was tried first and people missed it; cards make
/// every choice visible.
struct HomeView: View {
    let model: AppModel
    var pendingBriefing: Binding<PracticeDefinition?> = .constant(nil)
    let onStart: (PracticeSetup) -> Void
    var onOpenReport: (PracticeReport) -> Void = { _ in }
    var onStartCustom: (CustomSituation, PracticeSetup) -> Void = { _, _ in }

    /// Every page pushed from Practice, in order. One typed stack, so a
    /// back swipe always pops exactly the page on top: a situation page
    /// pushed one way and a briefing another left iOS unsure of their order,
    /// and swiping back from the briefing skipped past the situation page.
    @State private var path: [HomeRoute] = []
    @State private var showsCheckIn = false
    @State private var openingRetry = false
    @State private var planError: String?
    @State private var showsPrompt = false
    @State private var carouselCard: String?

    private var profile: CoachProfile? { model.profile }
    private var done: Set<String> { Set(model.history.records.compactMap(\.activityID)) }

    /// A preparation plan still in progress.
    private var preparation: (plan: PreparationPlan, next: PracticeDefinition, done: Int, total: Int)? {
        guard let plan = model.preparation.plan, let program = plan.program,
              let next = plan.next(in: model.history.records) else { return nil }
        return (plan, next, plan.completedIDs(in: model.history.records).count, program.practiceIDs.count)
    }

    /// Shown only once history has loaded, so a step is never drawn as
    /// undone and then ticked a moment later.
    private var plan: FirstPlan? {
        guard model.history.loaded, let plan = FirstPlan(profile: profile, records: model.history.records, startedRetries: model.history.startedRetries), !plan.isComplete else { return nil }
        return plan
    }

    /// The first session not yet done, their own kind of moment first.
    private var suggestion: PracticeDefinition? {
        let opener = profile?.moment?.firstPractice
        let catalog = PracticeCategory.ordered(firstFor: profile?.moment).flatMap(\.practices)
        let ordered = [opener].compactMap { $0 } + catalog
        return ordered.first { !done.contains($0.id) } ?? opener ?? ordered.first
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                MorningStage(depth: 0.2)
                ScrollView(showsIndicators: false) {
                    content
                        .padding(.top, Space.sm)
                        .padding(.bottom, Space.xxxl)
                }
            }
            .statusBarScrim()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .briefing(let practice):
                    BriefingView(practice: practice, onBack: back, onStart: onStart)
                case .section(let section):
                    SectionPage(
                        section: section,
                        done: done,
                        onBack: back,
                        onPick: { path.append(.briefing($0)) },
                        onCustom: { path.append(.custom) },
                        onPrompt: { showsPrompt = true },
                        onSlides: { path.append(.presentations) }
                    )
                case .preparation:
                    PreparationPlanView(model: model, onBack: back, onPractice: { path.append(.briefing($0)) })
                case .custom:
                    CustomSituationView(onBack: back, onStart: onStartCustom)
                case .presentations:
                    PresentationsView(store: model.presentations, onBack: back)
                }
            }
        }
        .fullScreenCover(isPresented: $showsPrompt) {
            PromptView(routine: model.routine, source: .practice) { showsPrompt = false }
        }
        .sheet(isPresented: $showsCheckIn) {
            if let plan = FirstPlan(profile: profile, records: model.history.records, startedRetries: model.history.startedRetries) {
                PlanCheckInView(plan: plan) { model.completePlan(readiness: $0) }
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            Analytics.enter("practice_home")
            openPendingBriefing()
        }
        .onChange(of: pendingBriefing.wrappedValue) { _, _ in openPendingBriefing() }
    }

    /// Lands on the briefing with Home already beneath it, so Back is Home.
    private func openPendingBriefing() {
        guard let practice = pendingBriefing.wrappedValue else { return }
        pendingBriefing.wrappedValue = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { path = [.briefing(practice)] }
    }

    private func back() {
        if !path.isEmpty { path.removeLast() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(greeting)
                .font(Typeface.hero(28))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Space.xxl)

            StreakCard(
                streak: model.history.streak,
                week: PracticeWeeks(records: model.history.records, weeks: 1),
                loaded: model.history.loaded
            )
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.lg)

            SectionTitle(text: String(localized: "For you", bundle: AppLanguage.bundle))
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xxxl)
            carousel
                .padding(.top, Space.md)

            SectionTitle(text: String(localized: "Situations", bundle: AppLanguage.bundle))
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xxxl)
            sections
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.md)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        guard let name = profile?.firstName, !name.isEmpty else {
            return switch hour {
            case 5..<12: String(localized: "Good morning", bundle: AppLanguage.bundle)
            case 12..<17: String(localized: "Good afternoon", bundle: AppLanguage.bundle)
            default: String(localized: "Good evening", bundle: AppLanguage.bundle)
            }
        }
        return switch hour {
        case 5..<12: String(localized: "Good morning, \(name)", bundle: AppLanguage.bundle, comment: "Slot: the user's first name.")
        case 12..<17: String(localized: "Good afternoon, \(name)", bundle: AppLanguage.bundle, comment: "Slot: the user's first name.")
        default: String(localized: "Good evening, \(name)", bundle: AppLanguage.bundle, comment: "Slot: the user's first name.")
        }
    }

    // MARK: For you

    private var cards: [(id: String, card: UpNext)] {
        var cards: [(String, UpNext)] = []
        if let upNext { cards.append(("next", upNext)) }
        if let recommended { cards.append(("recommended", recommended)) }
        if preparation == nil, plan == nil {
            cards.append(("prepare", UpNext(
                label: String(localized: "Plan ahead", bundle: AppLanguage.bundle),
                symbol: "calendar",
                title: String(localized: "Something coming up?", bundle: AppLanguage.bundle),
                meta: String(localized: "Five sessions that build to your date", bundle: AppLanguage.bundle),
                run: { path.append(.preparation) }
            )))
        }
        return cards
    }

    /// One card at a time, the next peeking in, snapping to each; dots
    /// below count them.
    private var carousel: some View {
        let cards = cards
        return VStack(spacing: Space.md) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Space.md) {
                    ForEach(cards, id: \.id) { item in
                        UpNextCard(
                            upNext: item.card,
                            isLoading: item.id == "next" && openingRetry,
                            error: item.id == "next" ? planError : nil,
                            softCover: item.id != "next"
                        )
                        .containerRelativeFrame(.horizontal) { width, _ in width - Space.xxl * 2 - (cards.count > 1 ? Space.xxl : 0) }
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Space.xxl, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $carouselCard)
            .scrollClipDisabled()

            if cards.count > 1 {
                HStack(spacing: 6) {
                    ForEach(cards, id: \.id) { item in
                        Capsule()
                            .fill((carouselCard ?? cards.first?.id) == item.id ? Palette.ink.opacity(0.55) : Palette.ink.opacity(0.14))
                            .frame(width: (carouselCard ?? cards.first?.id) == item.id ? 16 : 6, height: 6)
                    }
                }
                .animation(.snappy(duration: 0.25), value: carouselCard)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }
        }
    }

    private var upNext: UpNext? {
        if let plan, let step = plan.current {
            // The step marks say which step; the label only says whose.
            let label = String(localized: "Your plan", bundle: AppLanguage.bundle)
            let go = { advance(plan, step) }
            switch step {
            case .rehearse:
                return UpNext(label: label, step: step.rawValue, symbol: icon(plan.practice), title: plan.practice.title, meta: meta(plan.practice), run: go)
            case .retry:
                return UpNext(label: label, step: step.rawValue, symbol: "arrow.counterclockwise", title: String(localized: "Try one change", bundle: AppLanguage.bundle), meta: plan.practice.title, run: go)
            case .finish:
                return UpNext(
                    label: label, step: step.rawValue, symbol: "checkmark", title: String(localized: "Check in on how you feel", bundle: AppLanguage.bundle),
                    meta: plan.baseline.map { String(localized: "One question · you started at \($0)/10", bundle: AppLanguage.bundle) } ?? String(localized: "One question", bundle: AppLanguage.bundle),
                    run: go
                )
            }
        }
        if let preparation {
            return UpNext(
                label: String(localized: "Your event · \(preparation.done) of \(preparation.total) done", bundle: AppLanguage.bundle),
                symbol: icon(preparation.next),
                title: preparation.next.title,
                meta: meta(preparation.next),
                run: { path.append(.briefing(preparation.next)) }
            )
        }
        if let suggestion {
            return UpNext(label: String(localized: "Up next", bundle: AppLanguage.bundle), symbol: icon(suggestion), title: suggestion.title, meta: meta(suggestion), run: { path.append(.briefing(suggestion)) })
        }
        return nil
    }

    /// A scene with a hook, rotating daily among the ones not yet done and
    /// never the same as the card before it.
    private var recommended: UpNext? {
        let taken = [plan?.practice.id, preparation?.next.id, suggestion?.id].compactMap { $0 }
        let pool = Recommendation.all.filter { rec in
            guard let practice = rec.practice else { return false }
            if practice.id == "custom" { return !taken.contains(practice.id) && upNext?.title != practice.title }
            return !taken.contains(practice.id) && !done.contains(practice.id)
        }
        guard !pool.isEmpty, let pick = pool.rotating(by: Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0),
              let practice = pick.practice else { return nil }
        return UpNext(label: String(localized: "Recommended", bundle: AppLanguage.bundle), symbol: pick.symbol, title: pick.hook, meta: meta(practice), run: { path.append(.briefing(practice)) })
    }

    private func meta(_ practice: PracticeDefinition) -> String {
        practice.meta
    }

    private func icon(_ practice: PracticeDefinition) -> String {
        HomeSection.containing(practice)?.icon ?? "mic"
    }

    private func advance(_ plan: FirstPlan, _ step: FirstPlan.Step) {
        Analytics.action("home_plan", step: step.rawValue + 1)
        planError = nil
        switch step {
        case .rehearse:
            path.append(.briefing(plan.practice))
        case .retry:
            openRetry(plan)
        case .finish:
            showsCheckIn = true
        }
    }

    /// Step two reopens the session's own debrief — "Try one change" and
    /// the moment to retry are what make the retry mean anything — whose
    /// primary action is the retry. A report with no moment to go back to
    /// gets the whole scene again instead.
    private func openRetry(_ plan: FirstPlan) {
        guard let record = plan.retryFrom else { path.append(.briefing(plan.practice)); return }
        openingRetry = true
        Task {
            do {
                let report = try await model.history.report(id: record.id)
                if RetryCheckpoint.make(from: report) != nil {
                    onOpenReport(report)
                } else {
                    path.append(.briefing(plan.practice))
                }
            } catch {
                planError = String(localized: "Your last session couldn't be opened. Check your connection and try again.", bundle: AppLanguage.bundle)
            }
            openingRetry = false
        }
    }

    // MARK: Situations

    /// Four cards, two by two.
    private var sections: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.sm), GridItem(.flexible(), spacing: Space.sm)], spacing: Space.sm) {
            ForEach(HomeSection.allCases) { section in
                SectionCard(section: section) { path.append(.section(section)) }
            }
        }
    }
}

// MARK: - Routes

/// A page pushed from Practice.
enum HomeRoute: Hashable {
    case briefing(PracticeDefinition)
    case section(HomeSection)
    case preparation
    case custom
    case presentations
}

// MARK: - Sections

/// The four ways into practice on Home. Each is a page of its own.
enum HomeSection: String, CaseIterable, Identifiable, Hashable {
    case presentations, work, friends, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .presentations: String(localized: "Presentations", bundle: AppLanguage.bundle)
        case .work: String(localized: "Work & interviews", bundle: AppLanguage.bundle)
        case .friends: String(localized: "Friends & family", bundle: AppLanguage.bundle)
        case .custom: String(localized: "Custom & impromptu", bundle: AppLanguage.bundle)
        }
    }

    var subtitle: String {
        switch self {
        case .presentations: String(localized: "Open strong and keep the room with you.", bundle: AppLanguage.bundle)
        case .work: String(localized: "Interviews, updates, asks, and the hard talks.", bundle: AppLanguage.bundle)
        case .friends: String(localized: "Meet people and keep the conversation going.", bundle: AppLanguage.bundle)
        case .custom: String(localized: "Your own scene, or a quick one with no warning.", bundle: AppLanguage.bundle)
        }
    }

    var icon: String {
        switch self {
        case .presentations: "megaphone"
        case .work: "briefcase"
        case .friends: "person.2"
        case .custom: "bolt"
        }
    }

    /// Catalog sessions and built-in scenes on this page, in order.
    var practices: [PracticeDefinition] {
        switch self {
        case .presentations: PracticeCategory.big_moments.practices
        case .work: PracticeCategory.interviews.practices + PracticeCategory.work.practices + PracticeCategory.difficult.practices
        case .friends: PracticeCategory.social.practices
        case .custom: [CustomSituation.streetHello.definition]
        }
    }

    /// What the card counts: sessions, plus the page's own tools.
    var count: Int {
        switch self {
        case .presentations: practices.count + 1
        case .custom: practices.count + 2
        default: practices.count
        }
    }

    static func containing(_ practice: PracticeDefinition) -> HomeSection? {
        if practice.id == "custom" { return .custom }
        return allCases.first { $0.practices.contains { $0.id == practice.id } }
    }
}

/// A situation on Home: its glyph, its name, how much is inside.
private struct SectionCard: View {
    let section: HomeSection
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                glyph
                Spacer(minLength: Space.md)
                titles
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: Corner.lg, whiteness: 0.68, interactive: true)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens its sessions")
    }

    private var glyph: some View {
        Image(systemName: section.icon)
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(Palette.coralDeep)
            .frame(width: 28, height: 28, alignment: .leading)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(section.title)
                .font(Typeface.label(16))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(section.count) sessions", comment: "Number of sessions on a Home card. Pluralized.")
                .font(Typeface.body(13))
                .foregroundStyle(Palette.muted)
        }
    }
}

/// One situation's page: its sessions, then its own tools.
struct SectionPage: View {
    let section: HomeSection
    let done: Set<String>
    let onBack: () -> Void
    let onPick: (PracticeDefinition) -> Void
    let onCustom: () -> Void
    let onPrompt: () -> Void
    let onSlides: () -> Void

    var body: some View {
        SceneScreen(depth: 0.2) {
            SubpageHeader(title: section.title, subtitle: section.subtitle, onBack: onBack)
                .padding(.top, Space.md)

            GlassRowGroup {
                ForEach(Array(section.practices.enumerated()), id: \.offset) { index, practice in
                    if index > 0 { GlassRowDivider() }
                    sessionRow(practice)
                }
                switch section {
                case .presentations:
                    GlassRowDivider()
                    toolRow(title: String(localized: "Practice with my slides", bundle: AppLanguage.bundle), detail: String(localized: "Your own deck", bundle: AppLanguage.bundle), action: onSlides)
                case .custom:
                    GlassRowDivider()
                    toolRow(title: String(localized: "Custom situation", bundle: AppLanguage.bundle), detail: String(localized: "Describe any conversation", bundle: AppLanguage.bundle), action: onCustom)
                    GlassRowDivider()
                    toolRow(title: String(localized: "30-second prompt", bundle: AppLanguage.bundle), detail: String(localized: "One question, no warning", bundle: AppLanguage.bundle), action: onPrompt)
                default:
                    EmptyView()
                }
            }
            .padding(.top, Space.xxl)
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private func sessionRow(_ practice: PracticeDefinition) -> some View {
        let isDone = done.contains(practice.id)
        return Button {
            Haptics.selection()
            onPick(practice)
        } label: {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(practice.title)
                        .font(Typeface.label(16))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Text(practice.meta)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: Space.sm)
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.sage)
                        .accessibilityLabel("Done")
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.vertical, Space.md)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toolRow(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typeface.label(16))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: Space.sm)
                // Every row that opens something ends the same way.
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.vertical, Space.md)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recommendations

/// A scene sold by its moment, not its skill: what happens, in a line
/// short enough to read whole on the card (about 45 characters).
private struct Recommendation {
    let hook: String
    let symbol: String
    let practiceID: String?
    var builtIn: CustomSituation?

    var practice: PracticeDefinition? {
        if let builtIn { return builtIn.definition }
        return practiceID.flatMap(PracticeCatalog.definition)
    }

    static var all: [Recommendation] { [
        Recommendation(hook: String(localized: "A stranger stops you to chat. Don't freeze.", bundle: AppLanguage.bundle), symbol: "figure.walk", practiceID: nil, builtIn: .streetHello),
        Recommendation(hook: String(localized: "Your manager wants an update. Right now.", bundle: AppLanguage.bundle), symbol: "briefcase", practiceID: "clear_work_update"),
        Recommendation(hook: String(localized: "The interview question you didn't prepare for.", bundle: AppLanguage.bundle), symbol: "questionmark.bubble", practiceID: "interview_pressure"),
        Recommendation(hook: String(localized: "A colleague wants more. Say no, kindly.", bundle: AppLanguage.bundle), symbol: "hand.raised", practiceID: "set_a_boundary"),
        Recommendation(hook: String(localized: "A party, and someone new says hi.", bundle: AppLanguage.bundle), symbol: "person.2", practiceID: "meet_someone_new"),
        Recommendation(hook: String(localized: "You disagree in a meeting. Say it.", bundle: AppLanguage.bundle), symbol: "bubble.left.and.bubble.right", practiceID: "disagree_in_meeting"),
    ] }
}

private extension Array {
    /// A different element each day, going round.
    func rotating(by day: Int) -> Element? {
        isEmpty ? nil : self[((day % count) + count) % count]
    }
}

// MARK: - Streak

/// Showing up, at the top of Home: the streak big, the week as a disc per
/// day (ticked when practiced, today ringed), and whether today is done.
/// A zero streak wears the hollow grey flame; only a live one earns coral.
private struct StreakCard: View {
    let streak: Int
    let week: PracticeWeeks
    let loaded: Bool

    private static let disc: CGFloat = 30

    private var practicedToday: Bool { week.rows.last?.contains { $0.isToday && $0.count > 0 } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(alignment: .center, spacing: Space.md) {
                Image(systemName: streak > 0 ? "flame.fill" : "flame")
                    .font(.system(size: 30))
                    .foregroundStyle(streak > 0 ? Palette.coral : Palette.muted)
                VStack(alignment: .leading, spacing: 0) {
                    Text(loaded ? "\(streak)" : "–")
                        .font(Typeface.hero(30))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: Double(streak)))
                    Text("day streak", comment: "Under the streak number. Use a form that reads right after any number.")
                        .font(Typeface.label(13))
                        .foregroundStyle(Palette.dim)
                }
                Spacer(minLength: Space.sm)
                Label(practicedToday ? String(localized: "Done today", bundle: AppLanguage.bundle) : String(localized: "Practice today", bundle: AppLanguage.bundle), systemImage: practicedToday ? "checkmark.circle.fill" : "circle.dashed")
                    .font(Typeface.label(13))
                    .foregroundStyle(practicedToday ? Palette.sage : Palette.dim)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, 6)
                    .background(Capsule().fill((practicedToday ? Palette.sage : Palette.ink).opacity(0.08)))
            }

            HStack(spacing: 0) {
                ForEach(Array((week.rows.last ?? []).enumerated()), id: \.offset) { _, day in
                    VStack(spacing: Space.sm) {
                        disc(day)
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(Typeface.label(11))
                            .foregroundStyle(day.isToday ? Palette.ink : Palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Corner.lg, whiteness: 0.58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(practicedToday
            ? String(localized: "\(streak)-day streak. You've practiced today.", bundle: AppLanguage.bundle)
            : String(localized: "\(streak)-day streak. Not practiced yet today.", bundle: AppLanguage.bundle))
    }

    @ViewBuilder
    private func disc(_ day: PracticeWeeks.Day) -> some View {
        if day.count > 0 {
            Circle()
                .fill(Palette.coral)
                .frame(width: Self.disc, height: Self.disc)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
        } else if day.isToday {
            Circle()
                .strokeBorder(Palette.coral, lineWidth: 1.5)
                .frame(width: Self.disc, height: Self.disc)
        } else {
            Circle()
                .fill(Palette.ink.opacity(day.isFuture ? 0.04 : 0.08))
                .frame(width: Self.disc, height: Self.disc)
        }
    }
}

/// What the Up next card shows and does.
private struct UpNext {
    /// What kind of card it is: "Up next", "Recommended", the plan's step.
    var label: String?
    /// The first plan's step, drawn as three marks under the meta line.
    var step: Int?
    let symbol: String
    let title: String
    let meta: String
    let run: () -> Void
}

/// A section heading on the main tabs: "Up next", "History".
struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typeface.hero(22))
            .foregroundStyle(Palette.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

/// What to rehearse next. The coral panel is its cover; the whole card is
/// the button, and the chevron says so.
private struct UpNextCard: View {
    let upNext: UpNext
    var isLoading = false
    var error: String?
    /// Only the one thing to do next wears the full coral cover; the other
    /// cards in the carousel get a soft tint, so the screen isn't a wall of red.
    var softCover = false

    var body: some View {
        Button {
            Haptics.heavy()
            upNext.run()
        } label: {
            HStack(spacing: 0) {
                Group {
                    if softCover {
                        ZStack {
                            Palette.coral.opacity(0.1)
                            Image(systemName: upNext.symbol)
                                .font(.system(size: 30, weight: .regular))
                                .foregroundStyle(Palette.coralDeep)
                        }
                        .accessibilityHidden(true)
                    } else {
                        SessionCover(symbol: upNext.symbol, size: nil)
                    }
                }
                .frame(width: 84)

                VStack(alignment: .leading, spacing: 0) {
                    // The chevron rides the label's line, so the title below
                    // gets the column's whole width.
                    HStack(alignment: .center, spacing: Space.sm) {
                        Text(upNext.label ?? "")
                            .font(Typeface.label(13))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Group {
                            if isLoading {
                                ProgressView().tint(Palette.coral).controlSize(.small)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.dim)
                            }
                        }
                        .frame(width: 16, height: 16)
                    }
                    Text(upNext.title)
                        .font(Typeface.title(18))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.sm)

                    Spacer(minLength: Space.sm)

                    Text(error ?? upNext.meta)
                        .font(Typeface.body(13))
                        .foregroundStyle(error == nil ? Palette.muted : Palette.danger)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let step = upNext.step {
                        PlanSteps(current: step)
                            .padding(.top, Space.sm)
                    }
                }
                .padding(Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 168)
            .clipShape(RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: Corner.lg, whiteness: 0.76, interactive: true)
        .disabled(isLoading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A session's cover: the coral gradient with its situation's symbol. The
/// Up next card and the briefing share it, so one leads into the other.
/// `size` nil fills whatever frame it's given, square corners and all.
struct SessionCover: View {
    let symbol: String
    var size: CGFloat? = 88

    var body: some View {
        let cover = ZStack {
            LinearGradient(colors: [Palette.peach, Palette.coral], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: symbol)
                .font(.system(size: (size ?? 120) * 0.34, weight: .medium))
                .foregroundStyle(.white)
        }
        if let size {
            cover
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
                .accessibilityHidden(true)
        } else {
            cover.accessibilityHidden(true)
        }
    }
}

/// The first plan's three steps as short marks: done and current in coral.
private struct PlanSteps: View {
    let current: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Palette.coral : Palette.ink.opacity(0.1))
                    .frame(width: 16, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of 3")
    }
}

// MARK: - Categories

/// The catalog's own grouping, used to order suggestions.
enum PracticeCategory: String, CaseIterable {
    case interviews, work, difficult, big_moments, social

    /// The user's own kind of moment leads the list.
    static func ordered(firstFor moment: SpeakingMoment?) -> [PracticeCategory] {
        let lead: PracticeCategory? = switch moment {
        case .interview: .interviews
        case .raise, .speakingUp: .work
        case .hardConversation: .difficult
        case .presentation: .big_moments
        case .meetingPeople, .everyday: .social
        case nil: nil
        }
        guard let lead else { return allCases }
        return [lead] + allCases.filter { $0 != lead }
    }

    var practices: [PracticeDefinition] {
        PracticeCatalog.all.filter { $0.category == rawValue }
    }
}
