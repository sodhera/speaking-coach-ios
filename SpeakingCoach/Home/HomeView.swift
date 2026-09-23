import SwiftUI

/// Two tabs, each with one job — the SleepBlock shell. The system tab bar
/// becomes Liquid Glass on iOS 26 by itself.
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
                .tabItem { Label("Home", systemImage: "house.fill") }
            ProfileView(model: model, onOpenReport: onOpenReport)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Palette.coral)
    }
}

/// **Home — go rehearse.** A near-wordless instrument that never scrolls:
/// a small-caps greeting over the name, the bloom breathing at the centre as
/// the app's living state, the next rehearsal named in one glass capsule
/// beneath it, and one action where the thumb rests. Status sits at the
/// edges — the streak top-left, the full library top-right.
///
/// Until the first plan is done, Home *is* the plan: the card the user
/// committed to before the paywall, with its progress, and the primary
/// action names the next step. The library and Profile stay one tap away
/// for anyone who'd rather look around first.
struct HomeView: View {
    let model: AppModel
    var pendingBriefing: Binding<PracticeDefinition?> = .constant(nil)
    let onStart: (PracticeSetup) -> Void
    var onOpenReport: (PracticeReport) -> Void = { _ in }
    var onStartCustom: (CustomSituation, PracticeSetup) -> Void = { _, _ in }

    @State private var path: [PracticeDefinition] = []
    @State private var showsLibrary = false
    @State private var showsCheckIn = false
    @State private var openingRetry = false
    @State private var planError: String?
    @State private var showsPreparation = false

    private var profile: CoachProfile? { model.profile }
    private var upNext: PracticeDefinition? {
        preparation?.next
            ?? PracticeCatalog.definition(profile?.moment?.firstPracticeID ?? "interview_tell_me_about_yourself")
    }

    /// A preparation plan still in progress leads what's up next.
    private var preparation: (plan: PreparationPlan, next: PracticeDefinition, done: Int, total: Int)? {
        guard let plan = model.preparation.plan, let program = plan.program,
              let next = plan.next(in: model.history.records) else { return nil }
        return (plan, next, plan.completedIDs(in: model.history.records).count, program.practiceIDs.count)
    }

    /// Shown only once history has loaded, so a step is never drawn as
    /// undone and then ticked a moment later.
    private var plan: FirstPlan? {
        guard model.history.loaded, let plan = FirstPlan(profile: profile, records: model.history.records), !plan.isComplete else { return nil }
        return plan
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                MorningStage(depth: 0.2)
                content
                    .padding(.horizontal, Space.xxl)
                    .safeAreaPadding(.top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PracticeDefinition.self) { practice in
                BriefingView(practice: practice, onBack: { path.removeLast() }, onStart: onStart)
            }
            .navigationDestination(isPresented: $showsPreparation) {
                PreparationPlanView(model: model, onBack: { showsPreparation = false }, onPractice: { path.append($0) })
            }
        }
        .sheet(isPresented: $showsLibrary) {
            LibraryView(
                language: model.profile?.language ?? "en",
                presentations: model.presentations,
                model: model,
                onStart: { setup in
                    showsLibrary = false
                    onStart(setup)
                },
                onStartCustom: { situation, setup in
                    showsLibrary = false
                    onStartCustom(situation, setup)
                }
            )
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsCheckIn) {
            if let plan = FirstPlan(profile: profile, records: model.history.records) {
                PlanCheckInView(plan: plan) { model.completePlan(readiness: $0) }
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            Analytics.enter("home")
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
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                VStack(spacing: Space.sm) {
                    Kicker(text: greeting)
                    Text(profile?.firstName.isEmpty == false ? profile!.firstName : "Welcome")
                        .font(Typeface.hero(36))
                        .foregroundStyle(Palette.ink)
                }
                .padding(.top, Space.huge)

                HStack {
                    StreakChip(count: model.history.streak)
                    Spacer()
                    GlassIconButton(systemImage: "square.grid.2x2", size: 44, iconSize: 16, accessibilityLabel: "All rehearsals") {
                        showsLibrary = true
                    }
                }
            }

            Spacer(minLength: Space.xxxl)

            if let plan {
                // The bloom steps aside on short screens; the plan never does.
                ViewThatFits(in: .vertical) {
                    VStack(spacing: Space.xl) {
                        BloomMark(size: 96)
                        PlanCard(plan: plan, compact: true)
                    }
                    PlanCard(plan: plan, compact: true)
                }
                .transition(.opacity)
            } else {
                upNextStack.transition(.opacity)
            }

            Spacer(minLength: Space.xxxl)

            VStack(spacing: Space.lg) {
                if let plan, let step = plan.current {
                    PrimaryButton(title: actionTitle(step), systemImage: actionIcon(step), isLoading: openingRetry) {
                        advance(plan, step)
                    }
                    .disabled(openingRetry)
                    Text(planError ?? hint(plan, step))
                        .font(Typeface.body(14))
                        .foregroundStyle(planError == nil ? Palette.muted : Palette.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    PrimaryButton(title: "Start rehearsal", systemImage: "mic.fill") {
                        if let upNext { path.append(upNext) }
                    }
                    if let last = lastRehearsal {
                        Text(last)
                            .font(Typeface.body(14))
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
            .padding(.bottom, Space.xxxl)
        }
        .animation(.easeInOut(duration: 0.3), value: plan)
    }

    private var upNextStack: some View {
        VStack(spacing: Space.xxl) {
            BloomMark(size: 170)
            if let upNext {
                Button {
                    Haptics.heavy()
                    path.append(upNext)
                } label: {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "mic.fill").foregroundStyle(Palette.coral)
                        Text(upNext.title).foregroundStyle(Palette.ink)
                        Text("· \(upNext.durationMinutes) min").foregroundStyle(Palette.muted)
                    }
                    .font(Typeface.label(15))
                    .padding(.horizontal, Space.xl)
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassSurface(cornerRadius: 999, interactive: true)
                .accessibilityLabel("Up next: \(upNext.title), \(upNext.durationMinutes) minutes")
            }
            if let preparation {
                Button {
                    Haptics.heavy()
                    showsPreparation = true
                } label: {
                    Text("Your plan · \(preparation.done) of \(preparation.total) · \(PreparationPlanView.when(preparation.plan).lowercased())")
                        .font(Typeface.body(14))
                        .foregroundStyle(Palette.dim)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, -Space.md)
            }
        }
    }

    // MARK: The plan's next step

    private func actionTitle(_ step: FirstPlan.Step) -> String {
        switch step {
        case .rehearse: model.history.records.isEmpty ? "Start your first rehearsal" : "Rehearse it out loud"
        case .retry: "Retry the moment · 90 sec"
        case .finish: "Check in on how you feel"
        }
    }

    private func actionIcon(_ step: FirstPlan.Step) -> String {
        switch step {
        case .rehearse: "mic.fill"
        case .retry: "arrow.counterclockwise"
        case .finish: "checkmark"
        }
    }

    /// What the step is, in one line — the guide for someone new here.
    private func hint(_ plan: FirstPlan, _ step: FirstPlan.Step) -> String {
        switch step {
        case .rehearse: "Your partner asks. You answer out loud."
        case .retry: "Back to the one moment from your feedback."
        case .finish: plan.baseline.map { "One question. You started at \($0)/10." } ?? "One question, and your plan is done."
        }
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

    /// Step two reopens the rehearsal's own debrief — "Try one change" and
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
                planError = "Your last rehearsal couldn't be opened. Check your connection and try again."
            }
            openingRetry = false
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
    }

    /// Only when it can honestly be called recent — never a weeks-old date
    /// dressed up as "last".
    private var lastRehearsal: String? {
        guard let last = model.history.records.first,
              let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last.date), to: Calendar.current.startOfDay(for: .now)).day,
              days <= 6 else { return nil }
        let when = days == 0 ? "today" : days == 1 ? "yesterday" : "\(days) days ago"
        return "Last rehearsal \(when)"
    }
}

/// The streak at the top-left edge. It shows zero — a `0` where a number is
/// meant to grow is the invitation — but zero never *celebrates*: it wears
/// the hollow muted flame, and only a live streak earns the filled coral.
private struct StreakChip: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: count > 0 ? "flame.fill" : "flame")
                .foregroundStyle(count > 0 ? Palette.coral : Palette.muted)
            Text("\(count)")
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: Double(count)))
        }
        .font(Typeface.label(15))
        .padding(.horizontal, Space.md)
        .frame(minWidth: 44, minHeight: 44)
        .glassSurface(cornerRadius: 999)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count)-day streak")
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
                    Text("All rehearsals")
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
                            ownRow(icon: "square.and.pencil", title: "My own situation", detail: "Describe any conversation you need to have.") {
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
                                ownRow(icon: "alarm.fill", title: "Practice routine", detail: "A daily prompt, and speak to unlock your apps.") {
                                    routining = true
                                }
                            }
                            if presentations != nil {
                                GlassRowDivider()
                                ownRow(icon: "rectangle.on.rectangle", title: "Presentations", detail: "Rehearse a talk with your slides.") {
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
        guard let plan = model.preparation.plan, let program = plan.program else { return "Five rehearsals toward a date." }
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
        case .big_moments: "Big moments"
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
        case nil: nil
        }
        guard let lead else { return allCases }
        return [lead] + allCases.filter { $0 != lead }
    }
}
