import AVFAudio
import SwiftUI

/// Giving the talk, full screen. The slide is the instrument — big, swiped
/// like the real clicker — and a small bloom by the timer shows the
/// microphone is hearing you. Finishing is a hold, like the voice room.
struct RehearsalView: View {
    let store: PresentationStore
    let deck: PresentationDeck
    let language: String
    let onClose: () -> Void

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
    @Environment(\.scenePhase) private var scenePhase

    /// 32 kbps keeps 40 minutes inside the 10 MB transcription limit.
    private static let maxDuration: TimeInterval = 40 * 60

    private var audioURL: URL { store.folder(for: deck.id).appending(path: "\(rehearsalID.uuidString).m4a") }

    var body: some View {
        ZStack {
            MorningStage(depth: 0.8, ripples: false)
            Group {
                switch stage {
                case .ready: ready
                case .recording: recording
                case .processing(let step): processing(step)
                case .failed(let message, let canRetry): failed(message, canRetry: canRetry)
                case .done(let id):
                    NavigationStack {
                        RehearsalReviewView(store: store, deck: deck, rehearsalID: id, language: language, isFresh: true, onBack: onClose)
                    }
                }
            }
            .transition(.opacity)
        }
        .statusBarScrim()
        .animation(.easeInOut(duration: 0.35), value: stage)
        .persistentSystemOverlays(stage == .recording ? .hidden : .automatic)
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
                GlassIconButton(systemImage: "xmark", size: 44, iconSize: 15, color: Palette.dim, accessibilityLabel: "Close", action: onClose)
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
            PrimaryButton(title: "Start talking", systemImage: "mic.fill") { Task { await begin() } }
                .padding(.bottom, Space.lg)
        }
        .padding(.horizontal, Space.xxl)
    }

    private func begin() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            stage = .failed("Speaking Coach needs the microphone to hear your talk. Turn it on in Settings.", canRetry: false)
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
            stage = .failed((error as? LocalizedError)?.errorDescription ?? "The microphone couldn't start.", canRetry: true)
        }
    }

    // MARK: Recording

    private var recording: some View {
        VStack(spacing: 0) {
            HStack {
                GlassIconButton(systemImage: "xmark", size: 44, iconSize: 15, color: Palette.dim, accessibilityLabel: "Leave rehearsal") {
                    confirmingLeave = true
                }
                .confirmationDialog("Leave this rehearsal?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                    Button("Finish and get questions") { finish() }
                    Button("Discard recording", role: .destructive) {
                        recorder.stop()
                        try? FileManager.default.removeItem(at: audioURL)
                        onClose()
                    }
                }
                Spacer()
                HStack(spacing: Space.sm) {
                    BloomMark(size: 26, level: recorder.level, breathes: false, glow: false)
                    Text(Self.clock(recorder.elapsed))
                        .font(Typeface.label(15))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                }
                .padding(.horizontal, Space.lg)
                .frame(height: 44)
                .glassSurface(cornerRadius: 22)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recording, \(Self.clock(recorder.elapsed))")
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
                GlassIconButton(systemImage: "chevron.left", size: 52, iconSize: 17, accessibilityLabel: "Previous slide") {
                    withAnimation { slide = max(slide - 1, 0) }
                }
                .disabled(slide == 0)
                .opacity(slide == 0 ? 0.4 : 1)
                Text("\(slide + 1) / \(deck.slideCount)")
                    .font(Typeface.label(16))
                    .foregroundStyle(Palette.dim)
                    .monospacedDigit()
                    .frame(minWidth: 70)
                GlassIconButton(systemImage: "chevron.right", size: 52, iconSize: 17, accessibilityLabel: "Next slide") {
                    withAnimation { slide = min(slide + 1, deck.slideCount - 1) }
                }
                .disabled(slide == deck.slideCount - 1)
                .opacity(slide == deck.slideCount - 1 ? 0.4 : 1)
            }
            .padding(.top, Space.xl)

            Spacer(minLength: Space.lg)

            HoldCapsuleButton(title: "Hold to finish", systemImage: "checkmark") { finish() }
                .padding(.horizontal, Space.xxl)
                .padding(.bottom, Space.lg)
        }
    }

    // MARK: Processing

    private func finish() {
        guard stage == .recording else { return }
        let seconds = recorder.stop()
        durationMs = Int(seconds * 1000)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: audioURL.path)
        Analytics.action("presentation_rehearsal")
        guard seconds >= 10 else {
            try? FileManager.default.removeItem(at: audioURL)
            stage = .failed("That was too short to coach. Give at least part of the talk out loud.", canRetry: true)
            return
        }
        Task { await process() }
    }

    private func process() async {
        stage = .processing("Listening back to your talk…")
        let transcript: String
        do {
            transcript = try await PresentationAPI.transcribe(audioURL, language: language)
        } catch {
            stage = .failed((error as? LocalizedError)?.errorDescription ?? "Your talk couldn't be transcribed.", canRetry: false)
            return
        }
        guard !transcript.isEmpty else {
            stage = .failed("We couldn't hear any speech in that recording. Check the microphone isn't covered and try again.", canRetry: true)
            return
        }
        var rehearsal = PresentationRehearsal(
            id: rehearsalID, deckID: deck.id, startedAt: startedAt, durationMs: durationMs,
            audioFile: audioURL.lastPathComponent, transcript: transcript, slideEvents: events,
            questions: [], answers: []
        )
        // Saved before the questions, so a network failure never loses the talk.
        store.save(rehearsal)
        stage = .processing("Your audience is thinking of questions…")
        if let questions = try? await PresentationAPI.questions(deck: deck, transcript: transcript, events: events) {
            rehearsal.questions = questions
            store.save(rehearsal)
        }
        Haptics.success()
        stage = .done(rehearsal.id)
    }

    private func processing(_ step: String) -> some View {
        VStack(spacing: Space.xxl) {
            BloomMark(size: 150, level: 0.15)
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
            title: "That didn't work",
            message: message,
            primary: failurePrimary(canRetry: canRetry),
            secondary: StatusScreen.Action(title: "Close", run: onClose)
        )
    }

    private func failurePrimary(canRetry: Bool) -> StatusScreen.Action? {
        if AVAudioApplication.shared.recordPermission == .denied {
            return StatusScreen.Action(title: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
        if canRetry { return StatusScreen.Action(title: "Try again") { stage = .ready } }
        // The recording is still on disk: try the upload again.
        if FileManager.default.fileExists(atPath: audioURL.path) {
            return StatusScreen.Action(title: "Try again") { Task { await process() } }
        }
        return nil
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
