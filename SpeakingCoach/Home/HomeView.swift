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
                .tabItem { Label("Practice", image: "TabBloom") }
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
/// 3. **Situations.** Five cards, each its own page: Presentations, Work &
///    interviews, Friends & family, Custom & impromptu, IELTS.
///
/// A situation dropdown was tried first and people missed it; cards make
/// every choice visible.
struct HomeView: View {
    let model: AppModel
    var pendingBriefing: Binding<PracticeDefinition?> = .constant(nil)
    let onStart: (PracticeSetup) -> Void
    var onOpenReport: (PracticeReport) -> Void = { _ in }
    var onStartCustom: (CustomSituation, PracticeSetup) -> Void = { _, _ in }

    @State private var path: [PracticeDefinition] = []
    @State private var openSection: HomeSection?
    @State private var showsCheckIn = false
    @State private var openingRetry = false
    @State private var planError: String?
    @State private var showsPreparation = false
    @State private var showsCustom = false
    @State private var showsPresentations = false
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
            .navigationDestination(for: PracticeDefinition.self) { practice in
                BriefingView(practice: practice, onBack: { path.removeLast() }, onStart: onStart)
            }
            .navigationDestination(item: $openSection) { section in
                SectionPage(
                    section: section,
                    done: done,
                    onBack: { openSection = nil },
                    onPick: { path.append($0) },
                    onCustom: { showsCustom = true },
                    onPrompt: { showsPrompt = true },
                    onSlides: { showsPresentations = true }
                )
            }
            .navigationDestination(isPresented: $showsPreparation) {
                PreparationPlanView(model: model, onBack: { showsPreparation = false }, onPractice: { path.append($0) })
            }
            .navigationDestination(isPresented: $showsCustom) {
                CustomSituationView(language: profile?.language ?? "en", onBack: { showsCustom = false }, onStart: onStartCustom)
            }
            .navigationDestination(isPresented: $showsPresentations) {
                PresentationsView(store: model.presentations, language: profile?.language ?? "en", onBack: { showsPresentations = false })
            }
        }
        .fullScreenCover(isPresented: $showsPrompt) {
            PromptView(routine: model.routine, source: .practice, language: profile?.language ?? "en") { showsPrompt = false }
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
        withTransaction(transaction) { path = [practice] }
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

            SectionTitle(text: "For you")
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xxxl)
            carousel
                .padding(.top, Space.md)

            SectionTitle(text: "Situations")
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xxxl)
            sections
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.md)
        }
    }

    private var greeting: String {
        let hello = switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        guard let name = profile?.firstName, !name.isEmpty else { return hello }
        return "\(hello), \(name)"
    }

    // MARK: For you

    private var cards: [(id: String, card: UpNext)] {
        var cards: [(String, UpNext)] = []
        if let upNext { cards.append(("next", upNext)) }
        if let recommended { cards.append(("recommended", recommended)) }
        if preparation == nil, plan == nil {
            cards.append(("prepare", UpNext(
                label: "Plan ahead",
                symbol: "calendar",
                title: "Something coming up?",
                meta: "Five sessions that build to your date",
                run: { showsPreparation = true }
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
            let label = "Your plan"
            let go = { advance(plan, step) }
            switch step {
            case .rehearse:
                return UpNext(label: label, step: step.rawValue, symbol: icon(plan.practice), title: plan.practice.title, meta: meta(plan.practice), run: go)
            case .retry:
                return UpNext(label: label, step: step.rawValue, symbol: "arrow.counterclockwise", title: "Try one change", meta: plan.practice.title, run: go)
            case .finish:
                return UpNext(
                    label: label, step: step.rawValue, symbol: "checkmark", title: "Check in on how you feel",
                    meta: plan.baseline.map { "One question · you started at \($0)/10" } ?? "One question",
                    run: go
                )
            }
        }
        if let preparation {
            return UpNext(
                label: "Your event · \(preparation.done) of \(preparation.total) done",
                symbol: icon(preparation.next),
                title: preparation.next.title,
                meta: meta(preparation.next),
                run: { path.append(preparation.next) }
            )
        }
        if let suggestion {
            return UpNext(label: "Up next", symbol: icon(suggestion), title: suggestion.title, meta: meta(suggestion), run: { path.append(suggestion) })
        }
        return nil
    }

    /// A scene with a hook, rotating daily among the ones not yet done and
    /// never the same as the card before it.
    private var recommended: UpNext? {
        let taken = [plan?.practice.id, preparation?.next.id, suggestion?.id].compactMap { $0 }
        let pool = Recommendation.all.filter { rec in
            guard let practice = rec.practice else { return false }
            if practice.id == "custom" { return !taken.contains(practice.title) && !(upNext?.title == practice.title) }
            return !taken.contains(practice.id) && !done.contains(practice.id)
        }
        guard !pool.isEmpty, let pick = pool.rotating(by: Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0),
              let practice = pick.practice else { return nil }
        return UpNext(label: "Recommended", symbol: pick.symbol, title: pick.hook, meta: meta(practice), run: { path.append(practice) })
    }

    private func meta(_ practice: PracticeDefinition) -> String {
        "\(practice.partner) · \(practice.durationMinutes) min"
    }

    private func icon(_ practice: PracticeDefinition) -> String {
        HomeSection.containing(practice)?.icon ?? "mic"
    }

    private func advance(_ plan: FirstPlan, _ step: FirstPlan.Step) {
        Analytics.action("home_plan", step: step.rawValue + 1)
        planError = nil
        switch step {
        case .rehearse:
            path.append(plan.practice)
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
        guard let record = plan.retryFrom else { path.append(plan.practice); return }
        openingRetry = true
        Task {
            do {
                let report = try await model.history.report(id: record.id)
                if RetryCheckpoint.make(from: report) != nil {
                    onOpenReport(report)
                } else {
                    path.append(plan.practice)
                }
            } catch {
                planError = "Your last session couldn't be opened. Check your connection and try again."
            }
            openingRetry = false
        }
    }

    // MARK: Situations

    /// Four cards two by two, IELTS across the bottom.
    private var sections: some View {
        VStack(spacing: Space.sm) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.sm), GridItem(.flexible(), spacing: Space.sm)], spacing: Space.sm) {
                ForEach(HomeSection.allCases.filter { $0 != .ielts }) { section in
                    SectionCard(section: section) { openSection = section }
                }
            }
            SectionCard(section: .ielts, wide: true) { openSection = .ielts }
        }
    }
}

// MARK: - Sections

/// The five ways into practice on Home. Each is a page of its own.
enum HomeSection: String, CaseIterable, Identifiable, Hashable {
    case presentations, work, friends, custom, ielts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .presentations: "Presentations"
        case .work: "Work & interviews"
        case .friends: "Friends & family"
        case .custom: "Custom & impromptu"
        case .ielts: "IELTS"
        }
    }

    var subtitle: String {
        switch self {
        case .presentations: "Open strong and keep the room with you."
        case .work: "Interviews, updates, asks, and the hard talks."
        case .friends: "Meet people and keep the conversation going."
        case .custom: "Your own scene, or a quick one with no warning."
        case .ielts: "Speaking Part 1, with an examiner."
        }
    }

    var icon: String {
        switch self {
        case .presentations: "megaphone"
        case .work: "briefcase"
        case .friends: "person.2"
        case .custom: "bolt"
        case .ielts: "graduationcap"
        }
    }

    /// Catalog sessions and built-in scenes on this page, in order.
    var practices: [PracticeDefinition] {
        switch self {
        case .presentations: PracticeCategory.big_moments.practices
        case .work: PracticeCategory.interviews.practices + PracticeCategory.work.practices + PracticeCategory.difficult.practices
        case .friends: PracticeCategory.social.practices
        case .custom: [CustomSituation.streetHello.definition]
        case .ielts: [CustomSituation.ieltsSpeaking.definition]
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
        if practice.id == "custom" {
            return practice.title == CustomSituation.ieltsSpeaking.title ? .ielts : .custom
        }
        return allCases.first { $0.practices.contains { $0.id == practice.id } }
    }
}

/// A situation on Home: its glyph, its name, how much is inside.
private struct SectionCard: View {
    let section: HomeSection
    var wide = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Group {
                if wide {
                    HStack(spacing: Space.md) {
                        glyph
                        titles
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.faint)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        glyph
                        Spacer(minLength: Space.md)
                        titles
                    }
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: Corner.lg, interactive: true)
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
            Text(section.count == 1 ? "1 session" : "\(section.count) sessions")
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
                    toolRow(title: "Practice with my slides", detail: "Your own deck", action: onSlides)
                case .custom:
                    GlassRowDivider()
                    toolRow(title: "Custom situation", detail: "Describe any conversation", action: onCustom)
                    GlassRowDivider()
                    toolRow(title: "30-second prompt", detail: "One question, no warning", action: onPrompt)
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
                    Text("\(practice.partner) · \(practice.durationMinutes) min")
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

    static let all: [Recommendation] = [
        Recommendation(hook: "A stranger stops you to chat. Don't freeze.", symbol: "figure.walk", practiceID: nil, builtIn: .streetHello),
        Recommendation(hook: "Your manager wants an update. Right now.", symbol: "briefcase", practiceID: "clear_work_update"),
        Recommendation(hook: "The interview question you didn't prepare for.", symbol: "questionmark.bubble", practiceID: "interview_pressure"),
        Recommendation(hook: "A colleague wants more. Say no, kindly.", symbol: "hand.raised", practiceID: "set_a_boundary"),
        Recommendation(hook: "A party, and someone new says hi.", symbol: "person.2", practiceID: "meet_someone_new"),
        Recommendation(hook: "You disagree in a meeting. Say it.", symbol: "bubble.left.and.bubble.right", practiceID: "disagree_in_meeting"),
    ]
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
                    Text(streak == 1 ? "day streak" : "day streak")
                        .font(Typeface.label(13))
                        .foregroundStyle(Palette.dim)
                }
                Spacer(minLength: Space.sm)
                Label(practicedToday ? "Done today" : "Practice today", systemImage: practicedToday ? "checkmark.circle.fill" : "circle.dashed")
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
        .glassSurface(cornerRadius: Corner.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak)-day streak. \(practicedToday ? "You've practiced today." : "Not practiced yet today.")")
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
        .glassSurface(cornerRadius: Corner.lg, interactive: true)
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
                .shadow(color: Palette.coral.opacity(0.25), radius: 14, y: 6)
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

// MARK: - Library

/// Every rehearsal, grouped, one tap from its briefing.
struct LibraryView: View {
    var language = "en"
    var presentations: PresentationStore?
    /// Enables the preparation plan, which reads history and the profile.
    var model: AppModel?
    let onStart: (PracticeSetup) -> Void
    var onStartCustom: (CustomSituation, PracticeSetup) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var path: [PracticeDefinition] = []
    @State private var composing = false
    @State private var presenting = false
    @State private var planning = false
    @State private var routining = false

    var body: some View {
        NavigationStack(path: $path) {
            SceneScreen(depth: 0.2) {
                HStack(alignment: .center) {
                    Text("All sessions")
                        .font(Typeface.hero(28))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    GlassIconButton(systemImage: "xmark", size: 40, iconSize: 14, color: Palette.dim, accessibilityLabel: "Close") { dismiss() }
                }
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xxl)

                VStack(alignment: .leading, spacing: Space.xxl) {
                    // Your own material: anything the catalog doesn't have.
                    VStack(alignment: .leading, spacing: Space.md) {
                        Kicker(text: "Your own")
                        GlassRowGroup {
                            ownRow(icon: "square.and.pencil", title: "Custom situation", detail: "Describe any conversation you need to have.") {
                                composing = true
                            }
                            if let model {
                                GlassRowDivider()
                                ownRow(icon: "calendar", title: "Preparation plan", detail: planDetail(model)) {
                                    planning = true
                                }
                            }
                            if let model {
                                GlassRowDivider()
                                ownRow(icon: "alarm", title: "Practice routine", detail: "A daily prompt, and speak to unlock your apps.") {
                                    routining = true
                                }
                            }
                            if presentations != nil {
                                GlassRowDivider()
                                ownRow(icon: "rectangle.on.rectangle", title: "Presentations", detail: "Practice a talk with your slides.") {
                                    presenting = true
                                }
                            }
                        }
                    }

                    ForEach(PracticeCategory.allCases) { category in
                        let items = PracticeCatalog.all.filter { $0.category == category.rawValue }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: Space.md) {
                                Kicker(text: category.title)
                                GlassRowGroup {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { index, practice in
                                        if index > 0 { GlassRowDivider() }
                                        Button {
                                            Haptics.heavy()
                                            path.append(practice)
                                        } label: {
                                            HStack(spacing: Space.md) {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(practice.title).font(Typeface.label(16)).foregroundStyle(Palette.ink)
                                                    Text("\(practice.partner) · \(practice.durationMinutes) min")
                                                        .font(Typeface.body(13)).foregroundStyle(Palette.muted)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.faint)
                                            }
                                            .padding(.vertical, Space.md)
                                            .frame(minHeight: 60)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: PracticeDefinition.self) { practice in
                BriefingView(practice: practice, onBack: { path.removeLast() }, onStart: onStart)
            }
            .navigationDestination(isPresented: $composing) {
                CustomSituationView(language: language, onBack: { composing = false }, onStart: onStartCustom)
            }
            .navigationDestination(isPresented: $planning) {
                if let model {
                    PreparationPlanView(model: model, onBack: { planning = false }, onPractice: { path.append($0) })
                }
            }
            .navigationDestination(isPresented: $routining) {
                if let model {
                    RoutineView(routine: model.routine, language: language, onBack: { routining = false })
                }
            }
            .navigationDestination(isPresented: $presenting) {
                if let presentations {
                    PresentationsView(store: presentations, language: language, onBack: { presenting = false })
                }
            }
        }
    }

    private func planDetail(_ model: AppModel) -> String {
        guard let plan = model.preparation.plan, let program = plan.program else { return "Five sessions toward a date." }
        return "\(plan.completedIDs(in: model.history.records).count) of \(program.practiceIDs.count) done · \(PreparationPlanView.when(plan))"
    }

    private func ownRow(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            HStack(spacing: Space.md) {
                GlassRowIcon(icon: icon)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Typeface.label(16)).foregroundStyle(Palette.ink)
                    Text(detail).font(Typeface.body(13)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.faint)
            }
            .padding(.vertical, Space.md)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Categories

enum PracticeCategory: String, CaseIterable, Identifiable {
    case interviews, work, difficult, big_moments, social

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interviews: "Interviews"
        case .work: "Work"
        case .difficult: "Difficult conversations"
        case .big_moments: "Presentations"
        case .social: "Social"
        }
    }

    /// The user's own kind of moment leads the list.
    static func ordered(firstFor moment: SpeakingMoment?) -> [PracticeCategory] {
        let lead: PracticeCategory? = switch moment {
        case .interview: .interviews
        case .raise, .speakingUp: .work
        case .hardConversation: .difficult
        case .presentation: .big_moments
        case .meetingPeople, .everyday: .social
        // The IELTS scene is built in, not a catalog category.
        case .ielts, nil: nil
        }
        guard let lead else { return allCases }
        return [lead] + allCases.filter { $0 != lead }
    }

    var practices: [PracticeDefinition] {
        PracticeCatalog.all.filter { $0.category == rawValue }
    }

    var icon: String {
        switch self {
        case .interviews: "briefcase"
        case .work: "person.2"
        case .difficult: "bubble.left.and.bubble.right"
        case .big_moments: "megaphone"
        case .social: "hand.wave"
        }
    }

    var subtitle: String {
        switch self {
        case .interviews: "Answer out loud before the real thing."
        case .work: "Updates, disagreements and asks at work."
        case .difficult: "Say the hard thing clearly and kindly."
        case .big_moments: "Open strong and keep the room with you."
        case .social: "Meet people and keep the conversation going."
        }
    }
}
