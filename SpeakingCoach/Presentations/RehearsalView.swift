import AVFAudio
import SwiftUI

/// Giving the talk, full screen. The slide is the instrument — big, swiped
/// like the real clicker — and a small bloom by the timer shows the
/// microphone is hearing you. Finishing uses a clear confirmation.
struct RehearsalView: View {
    let store: PresentationStore
    let deck: PresentationDeck
    let onClose: () -> Void
    /// Drives a silent, deterministic recording preview in the DEBUG review gallery.
    var demoRecording = false

    enum Stage: Equatable {
        case ready
        case recording
        case processing(String)
        case failed(String, canRetry: Bool)
        case done(UUID)
    }

    @State private var stage: Stage = .ready
    @State private var recorder = AudioRecorder()
    @State private var slide = 0
    @State private var events: [SlideEvent] = []
    @State private var rehearsalID = UUID()
    @State private var startedAt = Date.now
    @State private var durationMs = 0
    @State private var confirmingLeave = false
    @State private var confirmingFinish = false
    @Environment(\.scenePhase) private var scenePhase

    /// 32 kbps keeps 40 minutes inside the 10 MB transcription limit.
    private static let maxDuration: TimeInterval = 40 * 60

    private var audioURL: URL { store.folder(for: deck.id).appending(path: "\(rehearsalID.uuidString).m4a") }

    var body: some View {
        ZStack {
            MorningStage(depth: 0.8)
            Group {
                switch stage {
                case .ready: ready
                case .recording: recording
                case .processing(let step): processing(step)
                case .failed(let message, let canRetry): failed(message, canRetry: canRetry)
                case .done(let id):
                    NavigationStack {
                        RehearsalReviewView(store: store, deck: deck, rehearsalID: id, isFresh: true, onBack: onClose)
                    }
                }
            }
            .transition(.opacity)
        }
        .statusBarScrim()
        .animation(.easeInOut(duration: 0.35), value: stage)
        .persistentSystemOverlays(stage == .recording ? .hidden : .automatic)
        .onAppear {
            if demoRecording {
                startedAt = .now
                events = [SlideEvent(slideIndex: 0, atMs: 0)]
                stage = .recording
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The microphone never stays live in the background: leaving
            // mid-talk ends it and keeps what you said.
            if phase == .background, stage == .recording { finish() }
        }
        .onChange(of: recorder.elapsed) { _, elapsed in
            if elapsed >= Self.maxDuration, stage == .recording { finish() }
        }
        .onDisappear { if recorder.isRecording { recorder.stop() } }
    }

    // MARK: Ready

    private var ready: some View {
        VStack(spacing: 0) {
            HStack {
                GlassIconButton(systemImage: "xmark", size: 44, iconSize: 15, color: Palette.dim, accessibilityLabel: String(localized: "Close", bundle: AppLanguage.bundle), action: onClose)
                Spacer()
            }
            .padding(.top, Space.md)
            Spacer()
            SlideImage(store: store, deck: deck.id, slide: 0, width: 300, cornerRadius: 12)
            VStack(spacing: Space.md) {
                Text("Give it like they're in the room")
                    .font(Typeface.hero(26))
                    .foregroundStyle(Palette.ink)
                Text("Speak out loud and swipe through your slides as you go. Afterwards, your audience asks questions.")
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.dim)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.top, Space.xxxl)
            Spacer()
            PrimaryButton(title: String(localized: "Start talking", bundle: AppLanguage.bundle), systemImage: "mic.fill") { Task { await begin() } }
                .padding(.bottom, Space.lg)
        }
        .padding(.horizontal, Space.xxl)
    }

    private func begin() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            stage = .failed(String(localized: "Speaking Coach needs the microphone to hear your talk. Turn it on in Settings.", bundle: AppLanguage.bundle), canRetry: false)
            return
        }
        rehearsalID = UUID()
        events = [SlideEvent(slideIndex: 0, atMs: 0)]
        slide = 0
        startedAt = .now
        do {
            try recorder.start(to: audioURL)
            Haptics.heavy()
            stage = .recording
            Analytics.enter("presentation_rehearsal")
        } catch {
            stage = .failed((error as? LocalizedError)?.errorDescription ?? String(localized: "The microphone couldn't start.", bundle: AppLanguage.bundle), canRetry: true)
        }
    }

    // MARK: Recording

    private var recording: some View {
        VStack(spacing: 0) {
            HStack {
                GlassIconButton(systemImage: "xmark", size: 44, iconSize: 15, color: Palette.dim, accessibilityLabel: String(localized: "Leave session", bundle: AppLanguage.bundle)) {
                    confirmingLeave = true
                }
                .confirmationDialog("Leave this session?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                    Button("Finish and get questions") { finish() }
                    Button("Discard recording", role: .destructive) {
                        recorder.stop()
                        try? FileManager.default.removeItem(at: audioURL)
                        onClose()
                    }
                }
                Spacer()
                TimelineView(.animation(minimumInterval: 1 / 12)) { timeline in
                    let elapsed = demoRecording ? max(0, timeline.date.timeIntervalSince(startedAt)) : recorder.elapsed
                    let level = demoRecording ? 0.2 + 0.72 * (0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 6.5)) : recorder.level
                    HStack(spacing: Space.sm) {
                        VoiceRods(size: 26, level: level, live: true)
                        Text(Self.clock(elapsed))
                            .font(Typeface.label(15))
                            .foregroundStyle(Palette.ink)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, Space.lg)
                    .frame(height: 44)
                    .glassSurface(cornerRadius: 22)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Recording, \(Self.clock(elapsed))")
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.md)

            Spacer(minLength: Space.lg)

            TabView(selection: $slide) {
                ForEach(0..<deck.slideCount, id: \.self) { index in
                    GeometryReader { proxy in
                        SlideImage(store: store, deck: deck.id, slide: index, width: proxy.size.width - Space.xl * 2, cornerRadius: 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: 360)
            .onChange(of: slide) { _, index in
                Haptics.selection()
                events.append(SlideEvent(slideIndex: index, atMs: Int(recorder.elapsed * 1000)))
            }

            HStack(spacing: Space.xl) {
                GlassIconButton(systemImage: "chevron.left", size: 52, iconSize: 17, accessibilityLabel: String(localized: "Previous slide", bundle: AppLanguage.bundle)) {
                    withAnimation { slide = max(slide - 1, 0) }
                }
                .disabled(slide == 0)
                .opacity(slide == 0 ? 0.4 : 1)
                Text("\(slide + 1) / \(deck.slideCount)")
                    .font(Typeface.label(16))
                    .foregroundStyle(Palette.dim)
                    .monospacedDigit()
                    .frame(minWidth: 70)
                GlassIconButton(systemImage: "chevron.right", size: 52, iconSize: 17, accessibilityLabel: String(localized: "Next slide", bundle: AppLanguage.bundle)) {
                    withAnimation { slide = min(slide + 1, deck.slideCount - 1) }
                }
                .disabled(slide == deck.slideCount - 1)
                .opacity(slide == deck.slideCount - 1 ? 0.4 : 1)
            }
            .padding(.top, Space.xl)

            Spacer(minLength: Space.lg)

            Button { confirmingFinish = true } label: {
                Label("Finish and get questions", systemImage: "checkmark")
                    .font(Typeface.label(16))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Capsule())
            }
                .buttonStyle(.plain)
                .glassSurface(cornerRadius: 999, interactive: true)
                .padding(.horizontal, Space.xxl)
                .padding(.bottom, Space.lg)
                .confirmationDialog("Finish this presentation?", isPresented: $confirmingFinish, titleVisibility: .visible) {
                    Button("Finish and get questions") { finish() }
                    Button("Keep speaking", role: .cancel) { }
                }
        }
    }

    // MARK: Processing

    private func finish() {
        guard stage == .recording else { return }
        #if DEBUG
        if demoRecording {
            let (_, rehearsal) = store.loadReviewFixture()
            stage = .done(rehearsal.id)
            return
        }
        #endif
        let seconds = recorder.stop()
        durationMs = Int(seconds * 1000)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: audioURL.path)
        Analytics.action("presentation_rehearsal")
        guard seconds >= 10 else {
            try? FileManager.default.removeItem(at: audioURL)
            stage = .failed(String(localized: "That was too short to coach. Give at least part of the talk out loud.", bundle: AppLanguage.bundle), canRetry: true)
            return
        }
        Task { await process() }
    }

    private func process() async {
        stage = .processing(String(localized: "Listening back to your talk…", bundle: AppLanguage.bundle))
        let transcript: String
        do {
            transcript = try await PresentationAPI.transcribe(audioURL, language: AppLanguage.code)
        } catch {
            stage = .failed((error as? LocalizedError)?.errorDescription ?? String(localized: "Your talk couldn't be transcribed.", bundle: AppLanguage.bundle), canRetry: false)
            return
        }
        guard !transcript.isEmpty else {
            stage = .failed(String(localized: "We couldn't hear any speech in that recording. Check the microphone isn't covered and try again.", bundle: AppLanguage.bundle), canRetry: true)
            return
        }
        var rehearsal = PresentationRehearsal(
            id: rehearsalID, deckID: deck.id, startedAt: startedAt, durationMs: durationMs,
            audioFile: audioURL.lastPathComponent, transcript: transcript, slideEvents: events,
            questions: [], answers: []
        )
        // Saved before the questions, so a network failure never loses the talk.
        store.save(rehearsal)
        stage = .processing(String(localized: "Your audience is thinking of questions…", bundle: AppLanguage.bundle))
        if let questions = try? await PresentationAPI.questions(deck: deck, transcript: transcript, events: events) {
            rehearsal.questions = questions
            store.save(rehearsal)
        }
        Haptics.success()
        Analytics.capture("presentation_rehearsed", [
            "duration_s": durationMs / 1000,
            "slides": deck.slideCount,
            "questions": rehearsal.questions.count,
        ])
        stage = .done(rehearsal.id)
    }

    private func processing(_ step: String) -> some View {
        VStack(spacing: Space.xxl) {
            VoiceRods(size: 150)
            Text(step)
                .font(Typeface.title(22))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, Space.xxl)
    }

    private func failed(_ message: String, canRetry: Bool) -> some View {
        StatusScreen(
            title: String(localized: "That didn't work", bundle: AppLanguage.bundle),
            message: message,
            primary: failurePrimary(canRetry: canRetry),
            secondary: StatusScreen.Action(title: String(localized: "Close", bundle: AppLanguage.bundle), run: onClose)
        )
    }

    private func failurePrimary(canRetry: Bool) -> StatusScreen.Action? {
        if AVAudioApplication.shared.recordPermission == .denied {
            return StatusScreen.Action(title: String(localized: "Open Settings", bundle: AppLanguage.bundle)) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
        if canRetry { return StatusScreen.Action(title: String(localized: "Try again", bundle: AppLanguage.bundle)) { stage = .ready } }
        // The recording is still on disk: try the upload again.
        if FileManager.default.fileExists(atPath: audioURL.path) {
            return StatusScreen.Action(title: String(localized: "Try again", bundle: AppLanguage.bundle)) { Task { await process() } }
        }
        return nil
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
