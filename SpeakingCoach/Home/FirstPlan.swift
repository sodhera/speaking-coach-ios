import SwiftUI

/// The plan the user committed to before the paywall — rehearse it, retry
/// the moment, walk in — kept after it. Progress is read from what actually
/// happened (the `reports` history and the plan's check-in), never stored
/// as a guess, so a second phone or a reinstall shows the same plan.
struct FirstPlan: Equatable {
    enum Step: Int, CaseIterable {
        case rehearse, retry, finish

        var title: String {
            switch self {
            case .rehearse: "Practice it out loud"
            case .retry: "Retry the moment that trips you up"
            case .finish: "" // In the user's own outcome — see `FirstPlan.title(of:)`.
            }
        }
    }

    let practice: PracticeDefinition
    let moment: SpeakingMoment
    /// The last step in the user's own words: "Walk in clear".
    let finish: String
    /// The step to do next; nil once the plan is done.
    let current: Step?
    /// The first plan rehearsal whose one retry is still unused — where
    /// step two goes back to.
    let retryFrom: PracticeRecord?
    let baseline: Int?

    /// Nil when there's no plan to keep: an old-app account (it never saw
    /// one), or a profile without a moment.
    /// `startedRetries`: sessions whose retry has begun on this phone. They
    /// don't count as the step done (no feedback came back), but step two
    /// can't send the user back to them either: the server allows one.
    init?(profile: CoachProfile?, records: [PracticeRecord], startedRetries: Set<UUID> = []) {
        guard let profile, !profile.isLegacy, let moment = profile.moment,
              let practice = moment.firstPractice else { return nil }
        self.practice = practice
        self.moment = moment
        finish = moment.planFinish(outcomes: profile.outcomes)
        baseline = profile.readiness

        let retried = Set(records.compactMap(\.parentID))
        let rehearsals: [PracticeRecord]
        let didRetry: Bool
        if let situation = moment.builtInSituation {
            // A built-in scene saves as a custom report: no catalog id, and
            // no focused retry — the second run of the scene is the retry.
            rehearsals = records.filter { $0.activityID == nil && $0.title == situation.title }
            didRetry = rehearsals.count > 1
            retryFrom = nil
        } else {
            rehearsals = records.filter { $0.activityID == practice.id && $0.parentID == nil }
            didRetry = rehearsals.contains { retried.contains($0.id) }
            retryFrom = rehearsals.first { !retried.contains($0.id) && !startedRetries.contains($0.id) }
        }

        if profile.planCompletedAt != nil {
            current = nil
        } else if rehearsals.isEmpty {
            current = .rehearse
        } else if !didRetry {
            current = .retry
        } else {
            current = .finish
        }
    }

    var isComplete: Bool { current == nil }

    func title(of step: Step) -> String {
        step == .finish ? finish : step.title
    }

    func isDone(_ step: Step) -> Bool {
        guard let current else { return true }
        return step.rawValue < current.rawValue
    }
}

// MARK: - The card

/// The plan as the user first saw it — the rehearsal on top, the three steps
/// beneath — now with its progress: done steps take the solid coral check,
/// the current one stands in ink, the rest wait in faint outline.
struct PlanCard: View {
    let plan: FirstPlan
    /// Home's version drops the partner line to save height.
    var compact = false

    private var kicker: String {
        guard let current = plan.current else { return "Your plan · done" }
        return "Your plan · step \(current.rawValue + 1) of 3"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Kicker(text: kicker, color: Palette.coralDeep)
                Text(plan.practice.title)
                    .font(Typeface.hero(compact ? 22 : 24))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(compact ? "\(plan.practice.durationMinutes) min · \(plan.practice.partner)" : "With \(plan.practice.partner.lowercasedFirst) · \(plan.practice.durationMinutes) min")
                    .font(Typeface.body(compact ? 14 : 15))
                    .foregroundStyle(Palette.dim)
                    .lineLimit(1)
            }
            .padding(compact ? Space.lg : Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)

            GlassRowDivider()

            VStack(alignment: .leading, spacing: compact ? Space.md : Space.lg) {
                ForEach(FirstPlan.Step.allCases, id: \.self) { step in
                    PlanStepRow(
                        number: step.rawValue + 1,
                        text: plan.title(of: step),
                        state: plan.isDone(step) ? .done : plan.current == step ? .current : .upcoming
                    )
                }
            }
            .padding(compact ? Space.lg : Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassSurface(cornerRadius: Corner.xl)
        .accessibilityElement(children: .combine)
    }
}

private struct PlanStepRow: View {
    enum Progress { case done, current, upcoming }

    let number: Int
    let text: String
    let state: Progress

    var body: some View {
        HStack(spacing: Space.md) {
            ZStack {
                switch state {
                case .done:
                    SelectionCheck(isSelected: true, size: 26)
                case .current:
                    Circle().fill(Palette.ink.opacity(0.85))
                    Text("\(number)").font(Typeface.label(14)).foregroundStyle(.white)
                case .upcoming:
                    Circle().strokeBorder(Palette.ink.opacity(0.22), lineWidth: 1.5)
                    Text("\(number)").font(Typeface.label(14)).foregroundStyle(Palette.muted)
                }
            }
            .frame(width: 26, height: 26)

            Text(text)
                .font(Typeface.label(16))
                .foregroundStyle(state == .upcoming ? Palette.muted : Palette.ink)
                .opacity(state == .done ? 0.6 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number), \(text), \(state == .done ? "done" : state == .current ? "up next" : "not started")")
    }
}

// MARK: - The check-in

/// The plan's last step. The app can't walk in with the user, so the honest
/// close is the question onboarding asked, asked again — the user's own
/// number read against their own baseline, never a score of ours.
struct PlanCheckInView: View {
    let plan: FirstPlan
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: Int
    @State private var touched = false
    @State private var saved = false

    init(plan: FirstPlan, onSave: @escaping (Int) -> Void) {
        self.plan = plan
        self.onSave = onSave
        _value = State(initialValue: plan.baseline ?? 5)
    }

    var body: some View {
        ZStack {
            MorningStage(depth: 1)
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    GlassIconButton(systemImage: "xmark", size: 40, iconSize: 14, color: Palette.dim, accessibilityLabel: "Close") { dismiss() }
                }
                .padding(.top, Space.lg)

                if saved {
                    result.transition(.opacity)
                } else {
                    question.transition(.opacity)
                }
            }
            .padding(.horizontal, Space.xxl)
            .padding(.bottom, Space.xxl)
        }
        .animation(.easeInOut(duration: 0.35), value: saved)
        .onAppear { Analytics.enter("plan_checkin") }
    }

    private var question: some View {
        VStack(spacing: 0) {
            QuestionLayout(
                title: plan.moment.readinessQuestion,
                readout: plan.baseline.map { "You started at \($0)." }
            ) {
                CoachSlider(
                    value: $value,
                    touched: $touched,
                    range: 0...10,
                    lowLabel: "Not at all",
                    highLabel: "Completely",
                    accessibilityName: "Readiness"
                )
            }
            .padding(.top, Space.xl)

            PrimaryButton(title: "Finish my plan") {
                Analytics.action("plan_checkin")
                onSave(value)
                Haptics.success()
                saved = true
            }
            .disabled(!touched)
        }
    }

    private var result: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Space.lg) {
                BloomMark(size: 96)
                Kicker(text: "Plan complete", color: Palette.coralDeep)
                HStack(spacing: Space.md) {
                    if let baseline = plan.baseline {
                        Text("\(baseline)").foregroundStyle(Palette.muted)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Palette.faint)
                    }
                    Text("\(value)").foregroundStyle(Palette.ink)
                }
                .font(Typeface.hero(56))
                Text(resultLine)
                    .font(Typeface.body(16))
                    .foregroundStyle(Palette.dim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            PrimaryButton(title: "Done") { dismiss() }
        }
    }

    /// Only what the two numbers say — no promise about the day itself.
    private var resultLine: String {
        guard let baseline = plan.baseline else { return "That's where you are today, by your own rating." }
        if value > baseline { return "Up from \(baseline) when you started." }
        if value == baseline { return "The same as when you started. Every session is still there when you want another go." }
        return plan.moment.isGeneral || plan.moment == .meetingPeople
            ? "Lower than when you started. That's worth another session."
            : "Lower than when you started. That's worth another session before the day."
    }
}
