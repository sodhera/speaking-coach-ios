import AVFAudio
import Observation
import SwiftUI

/// After the talk: the audience's questions first — that's the part people
/// dread and never practise — then the talk itself, replayed with the
/// slides following along.
struct RehearsalReviewView: View {
    let store: PresentationStore
    let deck: PresentationDeck
    let rehearsalID: UUID
    let language: String
    /// Just recorded: the header says so and closing leaves the rehearsal.
    var isFresh = false
    let onBack: () -> Void

    @State private var player = TalkPlayer()
    @State private var recorder = AudioRecorder()
    @State private var answering: String?
    @State private var working: String?
    @State private var loadingQuestions = false
    @State private var problem: String?
    @State private var showsTranscript = false

    private var rehearsal: PresentationRehearsal? {
        store.rehearsals[deck.id]?.first { $0.id == rehearsalID }
    }

    var body: some View {
        ZStack {
            MorningStage(depth: 0.3)
            if let rehearsal {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        header(rehearsal)
                        questions(rehearsal)
                        replay(rehearsal)
                        transcript(rehearsal)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, 80)
                }
                .safeAreaPadding(.top)
            }
        }
        .statusBarScrim()
        .toolbar(.hidden, for: .navigationBar)
        // A page with its own action at the bottom: the tab bar steps aside.
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if let rehearsal { player.load(store.audioURL(rehearsal)) }
            Analytics.enter("presentation_review")
        }
        .onDisappear {
            player.stop()
            if recorder.isRecording { recorder.stop() }
        }
    }

    private func leave() {
        player.stop()
        if recorder.isRecording { recorder.stop() }
        onBack()
    }

    // MARK: Header

    private func header(_ rehearsal: PresentationRehearsal) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if isFresh {
                GlassIconButton(systemImage: "xmark", size: 44, iconSize: 15, color: Palette.dim, accessibilityLabel: "Close", action: leave)
            } else {
                GlassBackButton(action: leave)
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                Kicker(text: isFresh ? "Session done" : rehearsal.startedAt.formatted(.dateTime.month(.wide).day().hour().minute()))
                Text(deck.title)
                    .font(Typeface.hero(28))
                    .foregroundStyle(Palette.ink)
                Text("\(DeckView.duration(rehearsal.durationMs)) talk · \(Self.wordsPerMinute(rehearsal)) words a minute")
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.dim)
            }
        }
    }

    /// Conversational pace sits around 130–160; nerves push it up.
    static func wordsPerMinute(_ rehearsal: PresentationRehearsal) -> Int {
        let words = rehearsal.transcript.split(whereSeparator: \.isWhitespace).count
        let minutes = max(Double(rehearsal.durationMs) / 60_000, 0.1)
        return Int((Double(words) / minutes).rounded())
    }

    // MARK: Questions

    @ViewBuilder
    private func questions(_ rehearsal: PresentationRehearsal) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Kicker(text: "Your audience asks")
            if rehearsal.questions.isEmpty {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text("The questions didn't come through.")
                        .font(Typeface.body(15))
                        .foregroundStyle(Palette.dim)
                    SecondaryButton(title: loadingQuestions ? "Asking…" : "Get audience questions", systemImage: "person.2.wave.2") {
                        Task { await loadQuestions(rehearsal) }
                    }
                    .disabled(loadingQuestions)
                }
            } else {
                Text("Answer out loud, like you would on the day. Each answer gets one specific note.")
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(rehearsal.questions.enumerated()), id: \.element.id) { index, question in
                    questionCard(index: index, question: question, answer: rehearsal.answers.first { $0.questionId == question.id }, rehearsal: rehearsal)
                }
            }
            if let problem {
                Text(problem)
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.coralDeep)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func questionCard(index: Int, question: AudienceQuestion, answer: QuestionAnswer?, rehearsal: PresentationRehearsal) -> some View {
        let isAnswering = answering == question.id
        let isWorking = working == question.id
        return VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text("\(index + 1)")
                    .font(Typeface.label(13))
                    .foregroundStyle(Palette.coralDeep)
                if let slide = question.slideIndex, slide < deck.slideCount {
                    Text("About slide \(slide + 1)")
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.muted)
                }
            }
            Text(question.question)
                .font(Typeface.title(19))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let answer, !isAnswering, !isWorking {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("You said")
                        .font(Typeface.label(13))
                        .foregroundStyle(Palette.muted)
                    Text(answer.transcript)
                        .font(Typeface.bodyItalic(15))
                        .foregroundStyle(Palette.dim)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: Space.md) {
                    GlassRowIcon(icon: "sparkle", color: Palette.coralDeep)
                    Text(answer.feedback)
                        .font(Typeface.body(15))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous).fill(Palette.coral.opacity(0.08)))
            }

            if isAnswering {
                HStack(spacing: Space.md) {
                    BloomMark(size: 30, level: recorder.level, breathes: false, glow: false)
                    Text("Listening · \(RehearsalView.clock(recorder.elapsed))")
                        .font(Typeface.label(15))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                    Spacer()
                }
                PrimaryButton(title: "Done answering", systemImage: "checkmark") {
                    Task { await finishAnswer(question, rehearsal: rehearsal) }
                }
            } else if isWorking {
                HStack(spacing: Space.md) {
                    ProgressView().tint(Palette.coral)
                    Text("Reading your answer…")
                        .font(Typeface.body(15))
                        .foregroundStyle(Palette.dim)
                }
                .frame(minHeight: 44)
            } else {
                SecondaryButton(title: answer == nil ? "Answer out loud" : "Answer again", systemImage: "mic.fill") {
                    Task { await startAnswer(question) }
                }
                .disabled(answering != nil || working != nil)
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Corner.lg)
        .animation(.easeInOut(duration: 0.25), value: isAnswering)
        .animation(.easeInOut(duration: 0.25), value: isWorking)
    }

    private var answerURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "presentation-answer.m4a")
    }

    private func startAnswer(_ question: AudienceQuestion) async {
        problem = nil
        player.pause()
        guard await AVAudioApplication.requestRecordPermission() else {
            problem = "Speaking Coach needs the microphone to hear your answer. Turn it on in Settings."
            return
        }
        do {
            try recorder.start(to: answerURL)
            answering = question.id
        } catch {
            problem = (error as? LocalizedError)?.errorDescription
        }
    }

    private func finishAnswer(_ question: AudienceQuestion, rehearsal: PresentationRehearsal) async {
        let seconds = recorder.stop()
        answering = nil
        defer { try? FileManager.default.removeItem(at: answerURL) }
        guard seconds >= 2 else {
            problem = "That answer was too short to hear. Try again."
            return
        }
        working = question.id
        defer { working = nil }
        do {
            let transcript = try await PresentationAPI.transcribe(answerURL, language: language)
            guard !transcript.isEmpty else {
                problem = "We couldn't hear an answer. Try again a little closer to the phone."
                return
            }
            let result = try await PresentationAPI.feedback(deck: deck, question: question, answer: transcript, talk: rehearsal.transcript)
            var updated = store.rehearsals[deck.id]?.first { $0.id == rehearsal.id } ?? rehearsal
            updated.answers.removeAll { $0.questionId == question.id }
            updated.answers.append(QuestionAnswer(questionId: question.id, transcript: transcript, feedback: result.feedback))
            store.save(updated)
            Haptics.success()
            Analytics.action("presentation_answer")
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "That didn't work. Please try again."
            Haptics.error()
        }
    }

    private func loadQuestions(_ rehearsal: PresentationRehearsal) async {
        loadingQuestions = true
        problem = nil
        defer { loadingQuestions = false }
        do {
            var updated = rehearsal
            updated.questions = try await PresentationAPI.questions(deck: deck, transcript: rehearsal.transcript, events: rehearsal.slideEvents)
            store.save(updated)
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "That didn't work. Please try again."
        }
    }

    // MARK: Replay

    private func replay(_ rehearsal: PresentationRehearsal) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Kicker(text: "Hear your talk")
            VStack(spacing: Space.lg) {
                GeometryReader { proxy in
                    SlideImage(store: store, deck: deck.id, slide: rehearsal.slide(atMs: Int(player.time * 1000)), width: proxy.size.width, cornerRadius: 10)
                }
                .aspectRatio(16 / 9, contentMode: .fit)

                HStack(spacing: Space.md) {
                    Button {
                        Haptics.heavy()
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Palette.coral))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    .disabled(!player.isReady || answering != nil)

                    VStack(spacing: 2) {
                        Slider(value: Binding(get: { player.time }, set: { player.seek($0) }), in: 0...max(player.duration, 0.1))
                            .tint(Palette.coral)
                        HStack {
                            Text(RehearsalView.clock(player.time))
                            Spacer()
                            Text(RehearsalView.clock(player.duration))
                        }
                        .font(Typeface.body(12))
                        .foregroundStyle(Palette.muted)
                        .monospacedDigit()
                    }
                }
            }
            .padding(Space.lg)
            .glassSurface(cornerRadius: Corner.lg)
            if !player.isReady {
#if DEBUG
                if rehearsal.audioFile == "missing.m4a" {
                    Text("Sample transcript · no audio recorded for this demo.")
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.muted)
                } else {
                    Text("The recording isn't on this phone any more.")
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.muted)
                }
#else
                Text("The recording isn't on this phone any more.")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.muted)
#endif
            }
        }
    }

    private func transcript(_ rehearsal: PresentationRehearsal) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Button {
                Haptics.selection()
                withAnimation(.easeInOut(duration: 0.25)) { showsTranscript.toggle() }
            } label: {
                HStack {
                    Kicker(text: "What you said")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.dim)
                        .rotationEffect(.degrees(showsTranscript ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsTranscript {
                Text(rehearsal.transcript)
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.dim)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }
}

/// Plays a rehearsal back and reports the time, so the slide can follow.
@MainActor
@Observable
final class TalkPlayer {
    private(set) var isPlaying = false
    private(set) var isReady = false
    private(set) var time: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    func load(_ url: URL) {
        guard player == nil, let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.prepareToPlay()
        self.player = player
        duration = player.duration
        isReady = true
    }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        if player.currentTime >= player.duration - 0.1 { player.currentTime = 0 }
        player.play()
        isPlaying = true
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let player = self.player else { return }
                self.time = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    return
                }
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
    }

    func seek(_ seconds: TimeInterval) {
        player?.currentTime = seconds
        time = seconds
    }

    func stop() {
        pause()
        player?.stop()
    }
}
