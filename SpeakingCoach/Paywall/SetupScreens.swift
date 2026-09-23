import AVFAudio
import SwiftUI
import UserNotifications

// The chain after the paywall, each on the same stage as the flow it closes:
// microphone → reminders → "You're all set!" → Home. Same grammar as
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

// MARK: - Microphone

struct MicrophonePrimerView: View {
    let onDone: () -> Void
    @State private var requesting = false

    var body: some View {
        PrimerLayout(
            title: "Your partner needs to hear you",
            line: "Speaking Coach only listens while you rehearse. Nothing is recorded outside a session."
        ) {
            MockPermissionDialog(
                glyph: "mic.fill",
                titleText: "\u{201C}Speaking Coach\u{201D} Would Like to Access the Microphone",
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
            title: "Keep your rehearsals going",
            line: "One quiet nudge at \(Reminders.timeLabel). You can turn it off anytime in Settings."
        ) {
            MockPermissionDialog(
                glyph: "bell.badge",
                titleText: "\u{201C}Speaking Coach\u{201D} Would Like to Send You Notifications",
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

/// The hand-off before Home: not a permission ask, just the settings the
/// user now has, each one a door, and a warm way in.
struct SetupCompleteView: View {
    let model: AppModel
    let onDone: () -> Void

    @State private var remindersOn = Reminders.isEnabled

    private var firstPractice: PracticeDefinition? {
        PracticeCatalog.definition(model.profile?.moment?.firstPracticeID ?? "interview_tell_me_about_yourself")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("You're all set!")
                    .font(Typeface.title(28))
                    .foregroundStyle(Palette.ink)
                Text("Your first rehearsal is waiting. You can change these anytime.")
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.dim)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: Space.xxl)

            GlassRowGroup {
                GlassRow(icon: "mic.fill", title: firstPractice?.title ?? "First rehearsal", value: firstPractice.map { "\($0.durationMinutes) min" })
                GlassRowDivider()
                Menu {
                    Picker("Practice language", selection: Binding(
                        get: { model.profile?.language ?? "en" },
                        set: { model.updateLanguage($0) }
                    )) {
                        ForEach(PracticeLanguage.all) { Text($0.name).tag($0.id) }
                    }
                } label: {
                    GlassRow(icon: "globe", title: "Practice language", value: PracticeLanguage.named(model.profile?.language ?? "en"), showsChevron: true)
                }
                GlassRowDivider()
                HStack(spacing: Space.md) {
                    GlassRowIcon(icon: "bell.fill")
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

            PrimaryButton(title: "Perfect!") {
                SetupChain.markComplete(userID: model.userID)
                onDone()
            }
        }
        .padding(.horizontal, Space.xxl)
        .padding(.bottom, Space.xxl)
        .onAppear { Analytics.enter("setup_complete") }
    }
}
