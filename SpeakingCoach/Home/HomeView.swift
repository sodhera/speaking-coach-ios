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
                .tabItem { Label("Practice", systemImage: "mic.fill") }
            ProgressScreen(model: model, onOpenReport: onOpenReport)
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
            ProfileView(model: model)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Palette.coral)
    }
}

/// Choose a situation first, then a rehearsal. Progress and an active plan
/// stay visible without taking over the practice catalog.
struct HomeView: View {
    let model: AppModel
    var pendingBriefing: Binding<PracticeDefinition?> = .constant(nil)
    let onStart: (PracticeSetup) -> Void
    var onOpenReport: (PracticeReport) -> Void = { _ in }
    var onStartCustom: (CustomSituation, PracticeSetup) -> Void = { _, _ in }

    @State private var path: [PracticeDefinition] = []
    @State private var showsCheckIn = false
    @State private var openingRetry = false
    @State private var planError: String?
    @State private var showsPreparation = false
    @State private var showsCustom = false
    @State private var showsPresentations = false
    @State private var showsPrompt = false
    @AppStorage("practice.selectedCategory") private var selectedCategoryID = ""

    private var profile: CoachProfile? { model.profile }
    private var selectedCategory: PracticeCategory {
        PracticeCategory(rawValue: selectedCategoryID)
            ?? PracticeCategory.ordered(firstFor: profile?.moment).first
            ?? .interviews
    }

    private var selectedPractices: [PracticeDefinition] {
        PracticeCatalog.all.filter { $0.category == selectedCategory.rawValue }
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
                ScrollView(showsIndicators: false) {
                    content
                        .padding(.horizontal, Space.xxl)
                        .padding(.top, Space.md)
                        .padding(.bottom, Space.xxxl)
                }
                .safeAreaPadding(.top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PracticeDefinition.self) { practice in
                BriefingView(practice: practice, onBack: { path.removeLast() }, onStart: onStart)
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
            if let plan = FirstPlan(profile: profile, records: model.history.records) {
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
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Practice")
                    .font(Typeface.hero(30))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: Space.lg) {
                    Label("\(model.history.lastSevenDays) this week", systemImage: "waveform")
                    Label("\(model.history.streak)-day streak", systemImage: "flame")
                }
                .font(Typeface.label(13))
                .foregroundStyle(Palette.dim)
                .accessibilityElement(children: .combine)
            }

            VStack(alignment: .leading, spacing: Space.md) {
                Text("What would you like to practice?")
                    .font(Typeface.title(21))
                    .foregroundStyle(Palette.ink)
                categoryChoices
            }

            VStack(alignment: .leading, spacing: Space.md) {
                Kicker(text: selectedCategory.title)
                GlassRowGroup {
                    ForEach(Array(selectedPractices.enumerated()), id: \.element.id) { index, practice in
                        if index > 0 { GlassRowDivider() }
                        practiceRow(practice)
                    }
                }
                Button { showsCustom = true } label: {
                    Label("Describe my own situation", systemImage: "square.and.pencil")
                        .font(Typeface.label(15))
                        .foregroundStyle(Palette.coralDeep)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }

            if let plan {
                VStack(alignment: .leading, spacing: Space.md) {
                    Kicker(text: "Continue your plan")
                    Text("\(plan.practice.title) · step \((plan.current?.rawValue ?? 0) + 1) of 3")
                        .font(Typeface.label(16))
                        .foregroundStyle(Palette.ink)
                    planAction(plan)
                }
                .padding(Space.lg)
                .glassSurface(cornerRadius: Corner.lg)
            }

            if let preparation {
                Button { showsPreparation = true } label: {
                    Label("Upcoming event · \(preparation.done) of \(preparation.total) rehearsed", systemImage: "calendar")
                        .font(Typeface.label(15))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                Button { showsPreparation = true } label: {
                    Label("Make a preparation plan", systemImage: "calendar.badge.plus")
                        .font(Typeface.label(15))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            Button { showsPrompt = true } label: {
                Label("Try today's 30-second prompt", systemImage: "mic")
                    .font(Typeface.label(15))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private var categoryChoices: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.sm) {
            ForEach(PracticeCategory.ordered(firstFor: profile?.moment)) { category in
                Button {
                    Haptics.selection()
                    selectedCategoryID = category.rawValue
                } label: {
                    Text(category.title)
                        .font(Typeface.label(14))
                        .foregroundStyle(selectedCategory == category ? .white : Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(selectedCategory == category ? Palette.coral : Color.white, in: RoundedRectangle(cornerRadius: Corner.md))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
            }
            Button { showsPresentations = true } label: {
                Text("My slides")
                    .font(Typeface.label(14))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Corner.md))
            }
            .buttonStyle(.plain)
        }
    }

    private func practiceRow(_ practice: PracticeDefinition) -> some View {
        Button { path.append(practice) } label: {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(practice.title).font(Typeface.label(16)).foregroundStyle(Palette.ink)
                    Text("\(practice.durationMinutes) min · \(practice.partner)")
                        .font(Typeface.body(13)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Palette.faint)
            }
            .padding(.vertical, Space.sm)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func planAction(_ plan: FirstPlan) -> some View {
        VStack(spacing: Space.sm) {
            if let step = plan.current {
                PrimaryButton(title: actionTitle(step), systemImage: actionIcon(step), isLoading: openingRetry) {
                    advance(plan, step)
                }
                .disabled(openingRetry)
                Text(planError ?? hint(plan, step))
                    .font(Typeface.body(14))
                    .foregroundStyle(planError == nil ? Palette.muted : Palette.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
        // The IELTS scene is built in, not a catalog category.
        case .ielts, nil: nil
        }
        guard let lead else { return allCases }
        return [lead] + allCases.filter { $0 != lead }
    }
}
