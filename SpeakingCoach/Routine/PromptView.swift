import AVFAudio
import SwiftUI

/// Today's prompt, full screen: one line to say, the bloom listening, and
/// a kind check. Opened by the daily reminder, by a shielded app's "Open
/// Speaking Coach", or by hand from the routine.
struct PromptView: View {
    enum Source: String { case unlock, reminder, practice }

    let routine: RoutineStore
    let source: Source
    let language: String
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

    init(routine: RoutineStore, source: Source, language: String, onClose: @escaping () -> Void) {
        self.routine = routine
        self.source = source
        self.language = language
        self.onClose = onClose
        _prompt = State(initialValue: DailyPrompt.today(language: language))
    }

    private var unlocks: Bool { routine.settings.unlockEnabled && routine.isSupported }
    private var answerURL: URL { FileManager.default.temporaryDirectory.appending(path: "daily-prompt.m4a") }

    var body: some View {
        ZStack {
            MorningStage(depth: 0.8, ripples: false)
            VStack(spacing: 0) {
                HStack {
                    GlassIconButton(systemImage: "xmark", size: 44, iconSize: 15, color: Palette.dim, accessibilityLabel: "Close") {
                        if recorder.isRecording { recorder.stop() }
                        onClose()
                    }
                    Spacer()
                }
                .padding(.top, Space.md)

                Spacer()

                BloomMark(size: 150, color: isPassed ? Palette.sage : Palette.coral, level: recorder.level)
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
        case .listening: "Listening · \(RehearsalView.clock(recorder.elapsed))"
        default: source == .unlock || (unlocks && routine.isShieldUp) ? "Speak to unlock" : "Today's prompt"
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
                PrimaryButton(title: stage == .ready ? "Start speaking" : "Try again", systemImage: "mic.fill") {
                    Task { await listen() }
                }
                skip
            case .listening:
                PrimaryButton(title: "Done", systemImage: "checkmark") { Task { await check() } }
            case .checking:
                PrimaryButton(title: "Checking", isLoading: true) {}
            case .passed:
                PrimaryButton(title: "Done", action: onClose)
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
                        QuietButton(title: "You can skip in \(left)s", color: Palette.muted) {}
                            .disabled(true)
                    } else {
                        QuietButton(title: "Skip — open my apps for \(Self.skipMinutes) minutes") {
                            routine.grant(minutes: Self.skipMinutes)
                            Analytics.action("daily_prompt_skip")
                            onClose()
                        }
                    }
                }
            } else {
                QuietButton(title: "Skip") { skipRequestedAt = .now }
            }
        } else if source != .practice {
            QuietButton(title: "Not now", action: onClose)
        }
    }

    private func listen() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            stage = .missed("Turn on the microphone for Speaking Coach in Settings.")
            return
        }
        do {
            try recorder.start(to: answerURL)
            Haptics.heavy()
            stage = .listening
        } catch {
            stage = .missed((error as? LocalizedError)?.errorDescription ?? "The microphone couldn't start.")
        }
    }

    private func check() async {
        guard stage == .listening else { return }
        recorder.stop()
        stage = .checking
        defer { try? FileManager.default.removeItem(at: answerURL) }
        do {
            let spokenLanguage = prompt.kind == .answer ? language : "en"
            let transcript = try await PresentationAPI.transcribe(answerURL, language: spokenLanguage)
            let result = prompt.evaluate(transcript)
            if result.passed {
                Haptics.success()
                Analytics.action("daily_prompt_\(source.rawValue)")
                if unlocks, routine.isShieldUp || source == .unlock {
                    routine.grant()
                    stage = .passed("\(result.note) Your apps are open for \(routine.settings.unlockMinutes) minutes.")
                } else {
                    stage = .passed(result.note)
                }
            } else {
                Haptics.error()
                stage = .missed(result.note)
            }
        } catch {
            stage = .missed("That couldn't be checked right now. Try again in a moment.")
        }
    }
}
