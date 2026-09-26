import AVFAudio
import SwiftUI
import UserNotifications

// The chain after the paywall, each on the same stage as the flow it closes:
// where they heard of us → microphone → reminders → "You're all set!" (the plan) → Home. Same grammar as
// SleepBlock's primers: one headline, one line, and a mock of the real
// system dialog so it's recognised on sight — the real request fires from
// the mock's own "Allow".

/// Which post-paywall beats this install still needs.
@MainActor
enum SetupChain {
    private static let micShownKey = "sc.micPrimerShown"
    private static let remindersShownKey = "sc.remindersPrimerShown"
    private static func completeKey(_ userID: UUID?) -> String { "sc.setupComplete.\(userID?.uuidString ?? "anon")" }

    static var needsMicrophone: Bool {
        !UserDefaults.standard.bool(forKey: micShownKey) && AVAudioApplication.shared.recordPermission == .undetermined
    }

    static func needsReminders() async -> Bool {
        guard !UserDefaults.standard.bool(forKey: remindersShownKey) else { return false }
        return await Reminders.authorizationStatus == .notDetermined
    }

    static func needsCompletion(userID: UUID?) -> Bool {
        !UserDefaults.standard.bool(forKey: completeKey(userID))
    }

    static func markMicrophoneShown() { UserDefaults.standard.set(true, forKey: micShownKey) }
    static func markRemindersShown() { UserDefaults.standard.set(true, forKey: remindersShownKey) }
    static func markComplete(userID: UUID?) { UserDefaults.standard.set(true, forKey: completeKey(userID)) }
}

// MARK: - Where they heard of us

/// One question, after the paywall rather than at step four: by now they've
/// paid, and an answer costs the business nothing. The flow's own grammar —
/// centred question, capsule answers, one button.
struct AttributionView: View {
    let onDone: (AcquisitionSource) -> Void
    @State private var choice: AcquisitionSource?

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { viewport in
                ScrollView {
                    QuestionLayout(title: String(localized: "How did you hear about us?", bundle: AppLanguage.bundle), subtitle: String(localized: "It helps us find people like you.", bundle: AppLanguage.bundle)) {
                        GlassGroup(spacing: Space.md) {
                            VStack(spacing: Space.md) {
                                ForEach(AcquisitionSource.allCases) { source in
                                    OptionRow(icon: source.icon, title: source.title, isSelected: choice == source) { choice = source }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height - Space.xxxl, alignment: .top)
                    .padding(.horizontal, Space.xxl)
                    .padding(.top, Space.xxxl)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
            PrimaryButton(title: String(localized: "Continue", bundle: AppLanguage.bundle)) {
                guard let choice else { return }
                Analytics.action("attribution")
                onDone(choice)
            }
            .disabled(choice == nil)
            .padding(.horizontal, Space.xxl)
            .padding(.bottom, Space.lg)
        }
        .onAppear { Analytics.enter("attribution") }
    }
}

// MARK: - Microphone

struct MicrophonePrimerView: View {
    let onDone: () -> Void
    @State private var requesting = false

    var body: some View {
        PrimerLayout(
            title: String(localized: "Your partner needs to hear you", bundle: AppLanguage.bundle),
            line: String(localized: "Speaking Coach only listens while you practice. Nothing is recorded outside a session.", bundle: AppLanguage.bundle)
        ) {
            MockPermissionDialog(
                glyph: "mic.fill",
                titleText: String(localized: "\u{201C}Speaking Coach\u{201D} Would Like to Access the Microphone", bundle: AppLanguage.bundle),
                isRequesting: requesting,
                onAllow: {
                    requesting = true
                    AVAudioApplication.requestRecordPermission { _ in
                        DispatchQueue.main.async { finish() }
                    }
                },
                onDeny: finish
            )
        }
        .onAppear { Analytics.enter("mic_primer") }
    }

    private func finish() {
        SetupChain.markMicrophoneShown()
        onDone()
    }
}

// MARK: - Reminders

struct RemindersPrimerView: View {
    let practiceTitle: String?
    let onDone: () -> Void
    @State private var requesting = false

    var body: some View {
        PrimerLayout(
            title: String(localized: "Keep your sessions going", bundle: AppLanguage.bundle),
            line: String(localized: "One quiet nudge at \(Reminders.timeLabel). You can turn it off anytime in Settings.", bundle: AppLanguage.bundle)
        ) {
            MockPermissionDialog(
                glyph: "bell.badge",
                titleText: String(localized: "\u{201C}Speaking Coach\u{201D} Would Like to Send You Notifications", bundle: AppLanguage.bundle),
                isRequesting: requesting,
                onAllow: {
                    requesting = true
                    Task {
                        await Reminders.enable(practiceTitle: practiceTitle)
                        finish()
                    }
                },
                onDeny: finish
            )
        }
        .onAppear { Analytics.enter("reminders_primer") }
    }

    private func finish() {
        SetupChain.markRemindersShown()
        onDone()
    }
}

/// Headline at the top, the dialog centred below it.
private struct PrimerLayout<Dialog: View>: View {
    let title: String
    let line: String
    @ViewBuilder var dialog: Dialog

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(title)
                    .font(Typeface.title(28))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line)
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.dim)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            dialog
            Spacer()
        }
        .padding(.horizontal, Space.xxl)
        .padding(.bottom, Space.xxl)
    }
}

// MARK: - You're all set

/// The hand-off before Home. For anyone who committed to a plan, it *is* the
/// plan again — the same card they held their thumb on before paying — and
/// the way in is step one. Looking around first is always allowed; Home keeps
/// the plan waiting either way.
struct SetupCompleteView: View {
    let model: AppModel
    /// `startFirst`: straight to the first rehearsal's briefing.
    let onDone: (_ startFirst: PracticeDefinition?) -> Void

    @State private var remindersOn = Reminders.isEnabled

    private var firstPractice: PracticeDefinition? {
        model.profile?.moment?.firstPractice ?? PracticeCatalog.definition("interview_tell_me_about_yourself")
    }

    private var plan: FirstPlan? { FirstPlan(profile: model.profile, records: model.history.records, startedRetries: model.history.startedRetries) }

    var body: some View {
        Group {
            if let plan {
                planHandOff(plan)
            } else {
                settingsHandOff
            }
        }
        .onAppear { Analytics.enter("setup_complete") }
    }

    private func planHandOff(_ plan: FirstPlan) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(model.profile?.firstName.isEmpty == false ? String(localized: "You're all set, \(model.profile!.firstName).", bundle: AppLanguage.bundle) : String(localized: "You're all set.", bundle: AppLanguage.bundle))
                    .font(Typeface.title(28))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Here's the plan you committed to. Step one takes about \(plan.practice.durationMinutes) minutes.")
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.dim)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .revealIn(after: 0.1)

            Spacer(minLength: Space.xxl)

            PlanCard(plan: plan)
                .revealIn(after: 0.35, rise: 14)

            Spacer(minLength: Space.xxl)

            VStack(spacing: Space.xs) {
                PrimaryButton(title: String(localized: "Start my first session", bundle: AppLanguage.bundle), systemImage: "mic.fill") {
                    Analytics.action("setup_complete")
                    finish(startFirst: plan.practice)
                }
                QuietButton(title: String(localized: "I'll look around first", bundle: AppLanguage.bundle)) {
                    finish(startFirst: nil)
                }
            }
        }
        .padding(.horizontal, Space.xxl)
        .padding(.bottom, Space.sm)
    }

    private func finish(startFirst: PracticeDefinition?) {
        SetupChain.markComplete(userID: model.userID)
        onDone(startFirst)
    }

    /// Accounts from the old app never saw a plan: the settings they now
    /// have, each one a door, and a warm way in.
    private var settingsHandOff: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("You're all set!")
                    .font(Typeface.title(28))
                    .foregroundStyle(Palette.ink)
                Text("Your first session is waiting. You can change these anytime.")
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.dim)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: Space.xxl)

            GlassRowGroup {
                GlassRow(icon: "mic", title: firstPractice?.title ?? String(localized: "First session", bundle: AppLanguage.bundle), value: firstPractice.map { String(localized: "\($0.durationMinutes) min", bundle: AppLanguage.bundle) })
                GlassRowDivider()
                HStack(spacing: Space.md) {
                    GlassRowIcon(icon: "bell")
                    Toggle(isOn: Binding(
                        get: { remindersOn },
                        set: { on in
                            Haptics.heavy()
                            if on {
                                Task { remindersOn = await Reminders.enable(practiceTitle: firstPractice?.title) }
                            } else {
                                Reminders.disable()
                                remindersOn = false
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily reminder").font(Typeface.body(16)).foregroundStyle(Palette.ink)
                            Text(Reminders.timeLabel).font(Typeface.body(13)).foregroundStyle(Palette.muted)
                        }
                    }
                    .tint(Palette.coral)
                }
                .padding(.vertical, Space.md)
            }

            Spacer(minLength: Space.xxl)

            PrimaryButton(title: String(localized: "Perfect!", bundle: AppLanguage.bundle)) { finish(startFirst: nil) }
        }
        .padding(.horizontal, Space.xxl)
        .padding(.bottom, Space.xxl)
    }
}
