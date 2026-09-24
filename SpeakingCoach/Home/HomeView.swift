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

/// **Practice — pick a situation, see what's in it.** Laid out the way a
/// music app lays out a library, because that's what this is: a shelf of
/// rehearsals, one of them picked for you, and the ones you've done.
///
/// 1. **Situation and streak.** The situation is a dropdown at the top left
///    ("Work ⌄"), remembered between visits; the streak sits top right.
/// 2. **The situation's rehearsals** as a grid of compact text tiles, a
///    tick on the ones already done, then "My own situation".
/// 3. **Up next.** One large card, the whole card a button with a chevron.
/// 4. **Recently practised.** A row of tiles, each reopening its feedback.
///
/// What's "up next" is decided for the user, in this order: the first plan
/// they committed to in onboarding, then a preparation plan in progress,
/// then the first rehearsal not yet done in the chosen situation, then
/// anywhere, their own kind of moment first.
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
    @State private var opening: UUID?
    @State private var openError: String?
    @State private var showsPreparation = false
    @State private var showsCustom = false
    @State private var showsPresentations = false
    @State private var showsPrompt = false
    @State private var showsSituations = false
    /// What to open once the situation popover has closed.
    @State private var afterPicker: (() -> Void)?
    @AppStorage("practice.selectedCategory") private var selectedCategoryID = ""

    private var profile: CoachProfile? { model.profile }
    private var categories: [PracticeCategory] { PracticeCategory.ordered(firstFor: profile?.moment) }
    private var done: Set<String> { Set(model.history.records.compactMap(\.activityID)) }

    /// Their last pick, else their own kind of moment.
    private var category: PracticeCategory {
        PracticeCategory(rawValue: selectedCategoryID) ?? categories.first ?? .interviews
    }

    /// A preparation plan still in progress.
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

    /// The first rehearsal not yet done in the chosen situation, then
    /// anywhere (their own moment's opener first). Everything done: the
    /// chosen situation's first.
    private var suggestion: PracticeDefinition? {
        let opener = profile?.moment?.firstPractice
        let anywhere = [opener].compactMap { $0 } + categories.flatMap { $0.practices }
        return category.practices.first { !done.contains($0.id) }
            ?? anywhere.first { !done.contains($0.id) }
            ?? category.practices.first
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                MorningStage(depth: 0.2)
                ScrollView(showsIndicators: false) {
                    content
                        .padding(.top, Space.md)
                        .padding(.bottom, Space.xxxl)
                }
                .safeAreaPadding(.top)
            }
            .statusBarScrim()
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Space.md) {
                situationMenu
                StreakChip(count: model.history.streak)
            }
            .padding(.horizontal, Space.xxl)

            tiles
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.lg)

            if let upNext {
                SectionTitle(text: "Up next")
                    .padding(.horizontal, Space.xxl)
                    .padding(.top, Space.xxxl)
                UpNextCard(upNext: upNext, isLoading: openingRetry, error: planError)
                    .padding(.horizontal, Space.xxl)
                    .padding(.top, Space.md)
            }

            let recent = Array(model.history.records.prefix(10))
            if !recent.isEmpty {
                SectionTitle(text: "Recently practised")
                    .padding(.horizontal, Space.xxl)
                    .padding(.top, Space.xxxl)
                recentRow(recent)
                    .padding(.top, Space.md)
                if let openError {
                    Text(openError)
                        .font(Typeface.body(14))
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Space.xxl)
                        .padding(.top, Space.sm)
                }
            }
        }
    }

    // MARK: Situation

    /// "Work ⌄". A popover, not a system menu: iOS 26 morphs a menu back
    /// into its label as it closes, and that morph drew the new name
    /// clipped. The popover leaves the label alone.
    private var situationMenu: some View {
        Button {
            Haptics.selection()
            showsSituations = true
        } label: {
            HStack(spacing: Space.sm) {
                Text(category.title)
                    .font(Typeface.hero(28))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.dim)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsSituations, attachmentAnchor: .point(UnitPoint(x: 0.2, y: 1)), arrowEdge: .top) {
            SituationPicker(
                categories: categories,
                selected: category,
                preparationDetail: preparation.map { "\($0.done) of \($0.total)" },
                onPick: { picked in
                    showsSituations = false
                    pick(picked)
                },
                onPrompt: { afterPicker = { showsPrompt = true }; showsSituations = false },
                onPreparation: { afterPicker = { showsPreparation = true }; showsSituations = false }
            )
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: showsSituations) { _, open in
            // A cover or a push waits until the popover has gone.
            guard !open, let next = afterPicker else { return }
            afterPicker = nil
            next()
        }
        .accessibilityLabel("Situation: \(category.title)")
        .accessibilityHint("Choose another situation")
    }

    private func pick(_ category: PracticeCategory) {
        Haptics.selection()
        // Not animated: the label swaps at once; only the tiles fade.
        selectedCategoryID = category.rawValue
    }

    /// The chosen situation's rehearsals, two to a row, then their own.
    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.sm), GridItem(.flexible(), spacing: Space.sm)], spacing: Space.sm) {
            ForEach(category.practices) { practice in
                RehearsalTile(title: practice.title, done: done.contains(practice.id)) {
                    path.append(practice)
                }
            }
            if category == .big_moments {
                RehearsalTile(title: "Practise with my slides", glyph: "rectangle.on.rectangle") { showsPresentations = true }
            }
            RehearsalTile(title: "My own situation", glyph: "square.and.pencil") { showsCustom = true }
        }
        .id(category)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: category)
    }

    // MARK: Recently practised

    private func recentRow(_ records: [PracticeRecord]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.md) {
                ForEach(records) { record in
                    RecentTile(record: record, isLoading: opening == record.id) { open(record) }
                        .disabled(opening != nil)
                }
            }
        }
        .contentMargins(.horizontal, Space.xxl, for: .scrollContent)
        .scrollClipDisabled()
    }

    private func open(_ record: PracticeRecord) {
        opening = record.id
        openError = nil
        Task {
            do { onOpenReport(try await model.history.report(id: record.id)) }
            catch { openError = "That session couldn't be opened. Check your connection and try again." }
            opening = nil
        }
    }

    // MARK: Up next

    private var upNext: UpNext? {
        if let plan, let step = plan.current {
            let label = "Your plan · step \(step.rawValue + 1) of 3"
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
            return UpNext(
                label: suggestion.category == category.rawValue ? nil : PracticeCategory(rawValue: suggestion.category)?.title,
                symbol: icon(suggestion),
                title: suggestion.title,
                meta: meta(suggestion),
                run: { path.append(suggestion) }
            )
        }
        return nil
    }

    private func meta(_ practice: PracticeDefinition) -> String {
        "\(practice.partner) · \(practice.durationMinutes) min"
    }

    private func icon(_ practice: PracticeDefinition) -> String {
        PracticeCategory(rawValue: practice.category)?.icon ?? "mic.fill"
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
                planError = "Your last session couldn't be opened. Check your connection and try again."
            }
            openingRetry = false
        }
    }
}

/// What the Up next card shows and does.
private struct UpNext {
    /// Only when it adds something: the plan or event it belongs to, or a
    /// situation other than the one already chosen above.
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

/// The streak, top right. Zero wears the hollow muted flame — a `0` where a
/// number is meant to grow is the invitation — and only a live streak
/// earns the filled coral.
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
        .frame(minWidth: 44, minHeight: 40)
        .glassSurface(cornerRadius: 999)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count)-day streak")
    }
}

/// The situations, then the two tools that aren't sessions. The current
/// situation wears a tick.
private struct SituationPicker: View {
    let categories: [PracticeCategory]
    let selected: PracticeCategory
    var preparationDetail: String?
    let onPick: (PracticeCategory) -> Void
    let onPrompt: () -> Void
    let onPreparation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(categories) { category in
                row(icon: category.icon, title: category.title, checked: category == selected) { onPick(category) }
            }
            GlassRowDivider()
                .padding(.vertical, Space.xs)
                .padding(.horizontal, Space.lg)
            row(icon: "timer", title: "30-second prompt", action: onPrompt)
            row(icon: "calendar", title: "Preparation plan", detail: preparationDetail, action: onPreparation)
        }
        .padding(.vertical, Space.sm)
        .frame(width: 290)
    }

    private func row(icon: String, title: String, checked: Bool = false, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.coralDeep)
                    .frame(width: 24)
                Text(title)
                    .font(Typeface.label(16))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: Space.sm)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.coral)
                } else if let detail {
                    Text(detail)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, Space.lg)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// A compact shelf tile: the title gets the width. A mark on the right
/// appears only where it says something — a tick once a rehearsal is done,
/// or the glyph of a tile that isn't a rehearsal (slides, their own).
private struct RehearsalTile: View {
    let title: String
    var done = false
    var glyph: String?
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: Space.sm) {
                Text(title)
                    .font(Typeface.label(14))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.coral)
                } else if let glyph {
                    Image(systemName: glyph)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.coralDeep)
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            // Both tiles in a row take the taller one's height.
            .frame(maxWidth: .infinity, minHeight: 60, maxHeight: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: Corner.sm, interactive: true)
        .accessibilityLabel(done ? "\(title), done" : title)
    }
}

/// What to rehearse next. The coral panel is its cover; the whole card is
/// the button, and the chevron says so.
private struct UpNextCard: View {
    let upNext: UpNext
    var isLoading = false
    var error: String?

    var body: some View {
        Button {
            Haptics.heavy()
            upNext.run()
        } label: {
            HStack(spacing: 0) {
                SessionCover(symbol: upNext.symbol, size: nil)
                    .frame(width: 120)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: Space.sm) {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            if let label = upNext.label {
                                Text(label)
                                    .font(Typeface.label(13))
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(1)
                            }
                            Text(upNext.title)
                                .font(Typeface.title(19))
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Group {
                            if isLoading {
                                ProgressView().tint(Palette.coral).controlSize(.small)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Palette.dim)
                            }
                        }
                        .frame(width: 16, height: 16)
                        .padding(.top, upNext.label == nil ? 4 : 0)
                    }

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
            .frame(minHeight: 150)
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

/// A session already done: its situation, its title, and when.
/// Opens the feedback it got.
private struct RecentTile: View {
    let record: PracticeRecord
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    GlassRowIcon(icon: record.parentID == nil ? ProgressScreen.icon(for: record) : "arrow.counterclockwise")
                    Spacer(minLength: Space.sm)
                    if isLoading {
                        ProgressView().tint(Palette.coral).controlSize(.small)
                    }
                }
                Spacer(minLength: Space.md)
                Text(record.title)
                    .font(Typeface.label(15))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ProgressScreen.day(record.date).capitalizedFirst + (record.parentID == nil ? "" : " · Retry"))
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(Space.lg)
            .frame(width: 156, height: 144, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: Corner.lg))
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: Corner.lg, interactive: true)
    }
}

private extension String {
    /// "on Monday" → "On Monday".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
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
                                ownRow(icon: "rectangle.on.rectangle", title: "Presentations", detail: "Practise a talk with your slides.") {
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
