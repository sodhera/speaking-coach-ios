import AVFAudio
import SwiftUI

/// Today's prompt, full screen: one line to say, the bloom listening, and
/// a kind check. Opened by the daily reminder, by a shielded app's "Open
/// Speaking Coach", or by hand from the routine.
struct PromptView: View {
    enum Source: String { case unlock, reminder, practice }

    let routine: RoutineStore
    let source: Source
    let onClose: () -> Void

    private enum Stage: Equatable {
        case ready, listening, checking
        case passed(String)
        case missed(String)
    }

    @State private var stage: Stage = .ready
    @State private var recorder = AudioRecorder()
    @State private var prompt: DailyPrompt
    @State private var skipRequestedAt: Date?

    /// Long enough for the urge to pass; short enough that nobody is trapped.
    private static let skipWait: TimeInterval = 10
    private static let skipMinutes = 5
    private static let maxAnswer: TimeInterval = 30

    init(routine: RoutineStore, source: Source, onClose: @escaping () -> Void) {
        self.routine = routine
        self.source = source
        self.onClose = onClose
        _prompt = State(initialValue: DailyPrompt.today())
    }

    private var unlocks: Bool { routine.settings.unlockEnabled && routine.isSupported }
    private var answerURL: URL { FileManager.default.temporaryDirectory.appending(path: "daily-prompt.m4a") }

    var body: some View {
        ZStack {
            MorningStage(depth: 0.8)
            VStack(spacing: 0) {
                HStack {
                    GlassIconButton(systemImage: "xmark", size: 44, iconSize: 15, color: Palette.dim, accessibilityLabel: String(localized: "Close", bundle: AppLanguage.bundle)) {
                        if recorder.isRecording { recorder.stop() }
                        onClose()
                    }
                    Spacer()
                }
                .padding(.top, Space.md)

                Spacer()

                VoiceRods(size: 150, color: isPassed ? Palette.sage : Palette.coral, level: recorder.level, live: stage == .listening)
                    .animation(.easeInOut(duration: 0.4), value: isPassed)

                VStack(spacing: Space.lg) {
                    Kicker(text: kicker, color: Palette.coralDeep)
                    Text(prompt.instruction)
                        .font(Typeface.body(16))
                        .foregroundStyle(Palette.dim)
                    Text(prompt.prompt)
                        .font(Typeface.title(26))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    feedback
                }
                .multilineTextAlignment(.center)
                .padding(.top, Space.xxxl)

                Spacer()

                actions
                    .padding(.bottom, Space.lg)
            }
            .padding(.horizontal, Space.xxl)
        }
        .statusBarScrim()
        .animation(.easeInOut(duration: 0.3), value: stage)
        .onChange(of: recorder.elapsed) { _, elapsed in
            if elapsed >= Self.maxAnswer, stage == .listening { Task { await check() } }
        }
        .onDisappear { if recorder.isRecording { recorder.stop() } }
        .onAppear { Analytics.enter("daily_prompt_\(source.rawValue)") }
    }

    private var isPassed: Bool { if case .passed = stage { true } else { false } }

    private var kicker: String {
        switch stage {
        case .listening: String(localized: "Listening · \(RehearsalView.clock(recorder.elapsed))", bundle: AppLanguage.bundle)
        default: source == .unlock || (unlocks && routine.isShieldUp) ? String(localized: "Speak to unlock", bundle: AppLanguage.bundle) : String(localized: "Today's prompt", bundle: AppLanguage.bundle)
        }
    }

    @ViewBuilder
    private var feedback: some View {
        switch stage {
        case .passed(let note):
            Text(note).font(Typeface.label(16)).foregroundStyle(Palette.sage).transition(.opacity)
        case .missed(let note):
            Text(note).font(Typeface.body(15)).foregroundStyle(Palette.coralDeep).transition(.opacity)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Space.sm) {
            switch stage {
            case .ready, .missed:
                PrimaryButton(title: stage == .ready ? String(localized: "Start speaking", bundle: AppLanguage.bundle) : String(localized: "Try again", bundle: AppLanguage.bundle), systemImage: "mic.fill") {
                    Task { await listen() }
                }
                skip
            case .listening:
                PrimaryButton(title: String(localized: "Done", bundle: AppLanguage.bundle), systemImage: "checkmark") { Task { await check() } }
            case .checking:
                PrimaryButton(title: String(localized: "Checking", bundle: AppLanguage.bundle), isLoading: true) {}
            case .passed:
                PrimaryButton(title: String(localized: "Done", bundle: AppLanguage.bundle), action: onClose)
            }
        }
    }

    /// The way out that always exists: ask, wait ten seconds, then open the
    /// apps for five minutes. The wait is the whole mechanism — most urges
    /// pass inside it — and it means no failure can ever lock anyone out.
    @ViewBuilder
    private var skip: some View {
        if unlocks, routine.isShieldUp {
            if let requested = skipRequestedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = Int(ceil(Self.skipWait - context.date.timeIntervalSince(requested)))
                    if left > 0 {
                        QuietButton(title: String(localized: "You can skip in \(left)s", bundle: AppLanguage.bundle), color: Palette.muted) {}
                            .disabled(true)
                    } else {
                        QuietButton(title: String(localized: "Skip and open my apps for \(Self.skipMinutes) minutes", bundle: AppLanguage.bundle, comment: "Pluralized.")) {
                            routine.grant(minutes: Self.skipMinutes)
                            Analytics.action("daily_prompt_skip")
                            onClose()
                        }
                    }
                }
            } else {
                QuietButton(title: String(localized: "Skip", bundle: AppLanguage.bundle)) { skipRequestedAt = .now }
            }
        } else if source != .practice {
            QuietButton(title: String(localized: "Not now", bundle: AppLanguage.bundle), action: onClose)
        }
    }

    private func listen() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            stage = .missed(String(localized: "Turn on the microphone for Speaking Coach in Settings.", bundle: AppLanguage.bundle))
            return
        }
        do {
            try recorder.start(to: answerURL)
            Haptics.heavy()
            stage = .listening
        } catch {
            stage = .missed((error as? LocalizedError)?.errorDescription ?? String(localized: "The microphone couldn't start.", bundle: AppLanguage.bundle))
        }
    }

    private func check() async {
        guard stage == .listening else { return }
        recorder.stop()
        stage = .checking
        defer { try? FileManager.default.removeItem(at: answerURL) }
        do {
            let transcript = try await PresentationAPI.transcribe(answerURL, language: AppLanguage.code)
            let result = prompt.evaluate(transcript)
            Analytics.capture("daily_prompt_result", ["passed": result.passed, "kind": prompt.kind.rawValue, "source": source.rawValue])
            if result.passed {
                Haptics.success()
                Analytics.action("daily_prompt_\(source.rawValue)")
                if unlocks, routine.isShieldUp || source == .unlock {
                    routine.grant()
                    stage = .passed("\(result.note) \(String(localized: "Your apps are open for \(routine.settings.unlockMinutes) minutes.", bundle: AppLanguage.bundle, comment: "Pluralized."))")
                } else {
                    stage = .passed(result.note)
                }
            } else {
                Haptics.error()
                stage = .missed(result.note)
            }
        } catch {
            stage = .missed(String(localized: "That couldn't be checked right now. Try again in a moment.", bundle: AppLanguage.bundle))
        }
    }
}
