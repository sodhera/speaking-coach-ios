import AVFAudio
import Combine
import ElevenLabs
import Foundation
import LiveKit
import Observation

/// One live conversation with the voice partner. Wraps the ElevenLabs SDK
/// and adds what the room needs on top: audio levels for the bloom, a pause
/// that truly silences both sides, the scene timer, a natural close, and a
/// transcript in the assessment endpoint's shape.
@MainActor
@Observable
final class VoiceSession {
    enum Phase: Equatable { case idle, connecting, live, ended }

    private(set) var phase: Phase = .idle
    private(set) var partnerSpeaking = false
    private(set) var isPaused = false
    /// Smoothed 0…1 levels, for the bloom.
    private(set) var inputLevel: Double = 0
    private(set) var outputLevel: Double = 0
    private(set) var transcript: [TranscriptLine] = []
    private(set) var remaining: Int = 0
    /// Set when the connection drops on its own (not by `end()`).
    private(set) var droppedUnexpectedly = false

    /// Called whenever the transcript changes, so it can be saved at once.
    var onTranscript: (([TranscriptLine]) -> Void)?
    /// Called when the scene has closed itself (turns used, or time up).
    var onNaturalEnd: (() -> Void)?

    private var conversation: Conversation?
    private var cancellables: Set<AnyCancellable> = []
    private var ticker: Task<Void, Never>?
    private let inputMeter = LevelMeter()
    private let outputMeter = LevelMeter()
    private var maxUserTurns = 3
    private var readyToClose = false
    private var lastActivity = Date.now
    private var pausedFor = 0
    private var overtime = 0
    private var endingByUser = false

    var userTurns: Int { transcript.filter { $0.role == .user }.count }
    var lastPartnerLine: String? { transcript.last { $0.role == .coach }?.text }

    #if DEBUG
    /// A live-looking room with no connection, for layout review.
    func loadReviewFixture() {
        phase = .live
        remaining = 184
        transcript = [
            TranscriptLine(id: "coach-1", role: .coach, text: "Thanks for coming in. So — tell me a little about yourself."),
            TranscriptLine(id: "user-1", role: .user, text: "I'm a designer who turns messy problems into simple tools."),
            TranscriptLine(id: "coach-2", role: .coach, text: "Interesting. What's one tool you made that people actually use every day?"),
        ]
        partnerSpeaking = true
        Task { @MainActor in
            var t = 0.0
            while phase == .live {
                t += 0.05
                outputLevel = max(0, 0.45 + 0.35 * sin(t * 7) * sin(t * 2.3))
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
    #endif

    // MARK: Lifecycle

    func start(token: String, prompt: String, language: String, duration: Int, maxUserTurns: Int) async throws {
        phase = .connecting
        remaining = duration
        self.maxUserTurns = maxUserTurns
        let config = ConversationConfig(
            agentOverrides: AgentOverrides(prompt: prompt, language: Language(rawValue: language) ?? .english)
        )
        let conversation = try await ElevenLabs.startConversation(conversationToken: token, config: config)
        self.conversation = conversation
        observe(conversation)
    }

    private func observe(_ conversation: Conversation) {
        conversation.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.handle(state) }
            .store(in: &cancellables)

        conversation.$agentState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                let speaking = state == .speaking
                if self.partnerSpeaking && !speaking { self.lastActivity = .now }
                self.partnerSpeaking = speaking
            }
            .store(in: &cancellables)

        conversation.$messages
            .receive(on: RunLoop.main)
            .sink { [weak self] messages in self?.handle(messages) }
            .store(in: &cancellables)

        inputMeter.onLevel = { [weak self] level in self?.inputLevel = self?.smooth(self?.inputLevel ?? 0, level) ?? 0 }
        outputMeter.onLevel = { [weak self] level in self?.outputLevel = self?.smooth(self?.outputLevel ?? 0, level) ?? 0 }
    }

    private func handle(_ state: ConversationState) {
        switch state {
        case .active:
            guard phase != .live else { return }
            phase = .live
            attachMeters()
            // The partner waits in silence for this; see `PracticePrompt`.
            Task { try? await conversation?.sendMessage(PracticePrompt.beginSignal) }
            startTicker()
        case .ended, .error:
            guard phase != .ended else { return }
            if !endingByUser { droppedUnexpectedly = true }
            teardown()
        default:
            break
        }
    }

    private func handle(_ messages: [Message]) {
        let lines = messages.compactMap { message -> TranscriptLine? in
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !PracticePrompt.isControlSignal(text) else { return nil }
            let role: TranscriptLine.Role = message.role == .user ? .user : .coach
            return TranscriptLine(id: "\(role.rawValue)-\(message.id)".prefix(150).description, role: role, text: String(text.prefix(6000)))
        }
        guard lines != transcript, !isPaused else { return }
        let hadUserWords = transcript.contains { $0.role == .user }
        transcript = Array(lines.suffix(100))
        lastActivity = .now
        onTranscript?(transcript)
        if let last = transcript.last, last.role == .coach, userTurns >= maxUserTurns { readyToClose = true }
        if !hadUserWords, transcript.contains(where: { $0.role == .user }) { firstUserWords?() }
    }

    /// Fired once, the first time the learner's own words arrive.
    var firstUserWords: (() -> Void)?

    // MARK: Controls

    /// Silences both sides: the mic is muted, the partner's audio drops to
    /// zero, and "user activity" pings keep the partner from filling the gap.
    func pause() {
        guard phase == .live, !isPaused else { return }
        isPaused = true
        pausedFor = 0
        Task {
            try? await conversation?.setMuted(true)
            conversation?.agentAudioTrack?.volume = 0
            try? await conversation?.interruptAgent()
        }
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        lastActivity = .now
        Task {
            conversation?.agentAudioTrack?.volume = 1
            try? await conversation?.setMuted(false)
            try? await conversation?.sendMessage(PracticePrompt.resumeSignal)
        }
    }

    func end() async {
        endingByUser = true
        await conversation?.endConversation()
        teardown()
    }

    private func teardown() {
        ticker?.cancel()
        ticker = nil
        if let track = conversation?.inputTrack { track.remove(audioRenderer: inputMeter) }
        if let track = conversation?.agentAudioTrack { track.remove(audioRenderer: outputMeter) }
        cancellables.removeAll()
        inputLevel = 0
        outputLevel = 0
        phase = .ended
    }

    // MARK: Timing and the natural close

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard phase == .live else { return }
        if isPaused {
            pausedFor += 1
            // Keep the partner from asking "are you still there?".
            if pausedFor % 8 == 0 { Task { try? await conversation?.interruptAgent() } }
            if pausedFor >= 90 { onNaturalEnd?() }
            return
        }
        if remaining > 0 {
            remaining -= 1
            if remaining == 0 {
                readyToClose = true
                Task { try? await conversation?.updateContext("Time is nearly up. Let the learner finish their current thought, then close warmly in one sentence.") }
            }
        } else {
            overtime += 1
            if overtime >= 45 { onNaturalEnd?() }
        }
        // Close once the scene has run its course and both sides have gone
        // quiet — never mid-sentence.
        if readyToClose, !partnerSpeaking, inputLevel < 0.05, Date.now.timeIntervalSince(lastActivity) > 3 {
            onNaturalEnd?()
        }
    }

    // MARK: Levels

    private func attachMeters() {
        conversation?.inputTrack?.add(audioRenderer: inputMeter)
        // The partner's track can arrive a beat after the room goes active.
        Task { [weak self] in
            for _ in 0..<20 {
                if let track = self?.conversation?.agentAudioTrack, let meter = self?.outputMeter {
                    track.add(audioRenderer: meter)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Fast attack, slow release — petals open with a syllable and settle
    /// back gently rather than flickering with every sample.
    private func smooth(_ current: Double, _ target: Double) -> Double {
        let rate = target > current ? 0.5 : 0.12
        return current + (target - current) * rate
    }
}

/// Reads raw PCM from a LiveKit track and reports a perceptual 0…1 level.
private final class LevelMeter: NSObject, AudioRenderer, @unchecked Sendable {
    var onLevel: (@MainActor (Double) -> Void)?

    func render(pcmBuffer: AVAudioPCMBuffer) {
        let frames = Int(pcmBuffer.frameLength)
        guard frames > 0 else { return }
        var sum: Float = 0
        if let samples = pcmBuffer.floatChannelData?[0] {
            for i in 0..<frames { sum += samples[i] * samples[i] }
        } else if let samples = pcmBuffer.int16ChannelData?[0] {
            for i in 0..<frames {
                let s = Float(samples[i]) / Float(Int16.max)
                sum += s * s
            }
        } else {
            return
        }
        let rms = sqrt(sum / Float(frames))
        // Map roughly -50…-10 dBFS onto 0…1.
        let db = 20 * log10(max(rms, 0.000_01))
        let level = Double(min(max((db + 50) / 40, 0), 1))
        Task { @MainActor [onLevel] in onLevel?(level) }
    }
}

/// Exposed for tests: whether the partner can speak a practice language.
enum ElevenLabsLanguageCheck {
    static func supports(_ code: String) -> Bool? {
        Language(rawValue: code) != nil ? true : nil
    }
}
