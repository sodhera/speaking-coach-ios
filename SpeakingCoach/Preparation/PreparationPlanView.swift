import SwiftUI

/// Preparation plan: five rehearsals in the order that builds, aimed at a
/// date if there is one. Progress is read from what you actually rehearsed —
/// never ticked by hand.
struct PreparationPlanView: View {
    let model: AppModel
    let onBack: () -> Void
    let onPractice: (PracticeDefinition) -> Void

    @State private var editing = false
    @State private var programID = ""
    @State private var eventName = ""
    @State private var hasDate = false
    @State private var eventDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var reminder = true
    @State private var outcome: PreparationPlan.Outcome?
    @State private var note = ""
    @State private var saving = false
    @State private var notice: String?
    @State private var confirmingRemove = false
    @FocusState private var focus: Field?

    private enum Field { case event, note }

    private var store: PreparationStore { model.preparation }
    private var plan: PreparationPlan? { store.plan }

    var body: some View {
        ZStack {
            MorningStage(depth: 0.3, ripples: false)
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        SubpageHeader(
                            title: "Preparation plan",
                            subtitle: editing || plan == nil
                                ? "Five sessions, in the order that builds. Add a date if something's coming up."
                                : nil,
                            onBack: onBack
                        )
                        if let plan, !editing {
                            progress(plan)
                        } else {
                            form
                        }
                        if let notice {
                            Text(notice)
                                .font(Typeface.body(14))
                                .foregroundStyle(Palette.coralDeep)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.huge)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaPadding(.top)
                .bottomEdgeFade()

                action
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.sm)
            }
        }
        .statusBarScrim()
        .toolbar(.hidden, for: .navigationBar)
        // A page with its own action at the bottom: the tab bar steps aside.
        .toolbar(.hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.25), value: editing)
        .animation(.easeInOut(duration: 0.25), value: hasDate)
        .onAppear {
            Analytics.enter(plan == nil ? "plan_create" : "plan_detail")
            fill(from: plan)
        }
        .confirmationDialog("Remove this plan?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove plan", role: .destructive) { Task { await save(nil) } }
        } message: {
            Text("Your sessions and feedback stay. Only the plan and its reminder go.")
        }
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            VStack(spacing: Space.md) {
                ForEach(PreparationProgram.all) { program in
                    ProgramRow(program: program, isSelected: programID == program.id) { programID = program.id }
                }
            }

            VStack(alignment: .leading, spacing: Space.sm) {
                Text("What's coming up? (optional)").font(Typeface.label(14)).foregroundStyle(Palette.dim)
                TextField("", text: $eventName, prompt: Text("e.g. my interview on Friday").foregroundStyle(Palette.muted))
                    .focused($focus, equals: .event)
                    .submitLabel(.done)
                    .modifier(InputChrome(focused: focus == .event))
                    .onChange(of: eventName) { _, value in
                        if value.count > 100 { eventName = String(value.prefix(100)) }
                    }
            }

            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: $hasDate.animation()) {
                    Text("It has a date").font(Typeface.body(16)).foregroundStyle(Palette.ink)
                }
                .tint(Palette.coral)
                .frame(minHeight: 52)
                if hasDate {
                    GlassRowDivider()
                    DatePicker("Date", selection: $eventDate, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                        .font(Typeface.body(16))
                        .foregroundStyle(Palette.ink)
                        .tint(Palette.coral)
                        .frame(minHeight: 52)
                    GlassRowDivider()
                    Toggle(isOn: $reminder) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remind me the day before").font(Typeface.body(16)).foregroundStyle(Palette.ink)
                            Text("At 9 am. The reminder never shows what it's for.")
                                .font(Typeface.body(13)).foregroundStyle(Palette.muted)
                        }
                    }
                    .tint(Palette.coral)
                    .padding(.vertical, Space.md)
                }
            }
            .padding(.horizontal, Space.lg)
            .glassSurface(cornerRadius: Corner.lg)
        }
    }

    // MARK: Progress

    private func progress(_ plan: PreparationPlan) -> some View {
        let practices = plan.program?.practices ?? []
        let done = plan.completedIDs(in: model.history.records)
        let next = plan.next(in: model.history.records)
        return VStack(alignment: .leading, spacing: Space.xxl) {
            VStack(alignment: .leading, spacing: Space.md) {
                Kicker(text: Self.when(plan), color: Palette.coralDeep)
                Text(plan.eventName.isEmpty ? (plan.program?.title ?? "Your plan") : plan.eventName)
                    .font(Typeface.title(24))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(practices, id: \.id) { practice in
                        Capsule()
                            .fill(done.contains(practice.id) ? Palette.coral : Palette.coral.opacity(0.15))
                            .frame(height: 6)
                    }
                }
                Text("\(done.count) of \(practices.count) done")
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.dim)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: Corner.lg)

            GlassRowGroup {
                ForEach(Array(practices.enumerated()), id: \.element.id) { index, practice in
                    if index > 0 { GlassRowDivider() }
                    Button {
                        Haptics.heavy()
                        onPractice(practice)
                    } label: {
                        HStack(spacing: Space.md) {
                            let isDone = done.contains(practice.id)
                            Image(systemName: isDone ? "checkmark.circle.fill" : practice.id == next?.id ? "circle.inset.filled" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(isDone || practice.id == next?.id ? Palette.coral : Palette.faint)
                            VStack(alignment: .leading, spacing: 2) {
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

            Text("Practising counts as done. Your feedback shows whether the skill is landing.")
                .font(Typeface.body(13))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            reflection(plan)

            HStack(spacing: Space.md) {
                SecondaryButton(title: "Edit plan") {
                    fill(from: plan)
                    editing = true
                }
                QuietButton(title: "Remove", color: Palette.danger) { confirmingRemove = true }
                    .frame(width: 100)
            }
        }
    }

    /// Asked once the day has come — or any time, for a plan without one.
    @ViewBuilder
    private func reflection(_ plan: PreparationPlan) -> some View {
        if (plan.daysUntilEvent() ?? 0) <= 0 {
            VStack(alignment: .leading, spacing: Space.md) {
                Kicker(text: "How did it go in real life?")
                ForEach(PreparationPlan.Outcome.allCases, id: \.self) { option in
                    OptionRow(icon: icon(option), title: option.label, isSelected: outcome == option) {
                        outcome = option
                    }
                }
                if outcome != nil {
                    TextField("", text: $note, prompt: Text("What helped? What was still hard? (optional)").foregroundStyle(Palette.muted), axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focus, equals: .note)
                        .modifier(InputChrome(focused: focus == .note))
                        .onChange(of: note) { _, value in
                            if value.count > 1000 { note = String(value.prefix(1000)) }
                        }
                    if outcome != plan.reflection?.outcome || note != (plan.reflection?.note ?? "") {
                        PrimaryButton(title: "Save reflection", isLoading: saving) {
                            var updated = plan
                            updated.reflection = PreparationPlan.Reflection(outcome: outcome!, note: note.trimmingCharacters(in: .whitespacesAndNewlines), recordedAt: .now)
                            Task { await save(updated) }
                        }
                    }
                }
            }
        }
    }

    private func icon(_ outcome: PreparationPlan.Outcome) -> String {
        switch outcome {
        case .used: "checkmark.seal"
        case .notYet: "hourglass"
        case .didNotHappen: "calendar.badge.minus"
        }
    }

    static func when(_ plan: PreparationPlan) -> String {
        guard let days = plan.daysUntilEvent() else { return plan.eventName.isEmpty ? "At your own pace" : plan.program?.title ?? "" }
        switch days {
        case ..<0: return "It's been and gone"
        case 0: return "It's today"
        case 1: return "Tomorrow"
        default: return "In \(days) days"
        }
    }

    // MARK: Action

    @ViewBuilder
    private var action: some View {
        if let plan, !editing {
            if let next = plan.next(in: model.history.records) {
                PrimaryButton(title: "Practise: \(next.title)", systemImage: "mic.fill") { onPractice(next) }
            }
        } else {
            VStack(spacing: Space.xs) {
                PrimaryButton(title: plan == nil ? "Start this plan" : "Save changes", isLoading: saving) {
                    focus = nil
                    Task { await save(draft) }
                }
                .disabled(programID.isEmpty)
                if plan != nil {
                    QuietButton(title: "Cancel") {
                        fill(from: plan)
                        editing = false
                    }
                }
            }
        }
    }

    private var draft: PreparationPlan {
        PreparationPlan(
            programID: programID,
            eventName: eventName.trimmingCharacters(in: .whitespacesAndNewlines),
            eventDate: hasDate ? Calendar.current.startOfDay(for: eventDate) : nil,
            reminderEnabled: hasDate && reminder,
            // Switching programs starts the count again; editing the date doesn't.
            createdAt: plan?.programID == programID ? plan!.createdAt : .now,
            reflection: plan?.programID == programID ? plan?.reflection : nil
        )
    }

    private func fill(from plan: PreparationPlan?) {
        programID = plan?.programID ?? PreparationProgram.suggested(for: model.profile?.moment).id
        eventName = plan?.eventName ?? ""
        hasDate = plan?.eventDate != nil
        if let date = plan?.eventDate { eventDate = date }
        reminder = plan?.reminderEnabled ?? true
        outcome = plan?.reflection?.outcome
        note = plan?.reflection?.note ?? ""
    }

    private func save(_ plan: PreparationPlan?) async {
        saving = true
        notice = nil
        defer { saving = false }
        do {
            let outcome = try await store.save(plan)
            Haptics.success()
            Analytics.action(plan == nil ? "plan_remove" : "plan_save")
            if case .savedWithoutReminder(let message) = outcome { notice = message }
            editing = false
            if plan == nil { fill(from: nil) }
        } catch {
            Haptics.error()
            notice = (error as? LocalizedError)?.errorDescription
        }
    }
}

private struct ProgramRow: View {
    let program: PreparationProgram
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: Space.md) {
                GlassRowIcon(icon: program.icon, color: isSelected ? Palette.coralDeep : Palette.dim)
                VStack(alignment: .leading, spacing: 3) {
                    Text(program.title).font(Typeface.label(16)).foregroundStyle(Palette.ink)
                    Text(program.detail).font(Typeface.body(13)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: Space.sm)
                SelectionCheck(isSelected: isSelected)
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Selection is drawn inside the glass: overlays get absorbed.
            .background {
                RoundedRectangle(cornerRadius: Corner.lg, style: .continuous)
                    .fill(Palette.coral.opacity(isSelected ? 0.10 : 0))
                    .strokeBorder(Palette.coral.opacity(isSelected ? 1 : 0), lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: Corner.lg, interactive: true)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
