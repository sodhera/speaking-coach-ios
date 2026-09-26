import AVFAudio
import Foundation
import Observation
import UIKit

/// Drives one rehearsal from setup to feedback: microphone → start the
/// attempt (the server checks the plan and mints the voice token) → the live
/// scene → assessment → the debrief. Every change to the transcript is saved
/// at once, so a crash, a dropped call or a killed app never loses words
/// already spoken — the next launch offers to finish their feedback.
@MainActor
@Observable
final class PracticeSession {
    enum Stage: Equatable {
        case preparing
        case live
        case assessing
        case report(PracticeReport)
        case recovery(PracticeDraft)
        case failed(Failure)
    }

    struct Failure: Equatable {
        var title: String
        var message: String
        var micDenied = false
        /// Words were captured, so feedback is still possible.
        var canAssess = false
        var canRetry = true
        /// Offer the whole scene again rather than the same doomed request.
        var offersFresh = false
    }

    private(set) var stage: Stage = .preparing
    /// A fresh connection for every attempt — a retry never inherits the
    /// last scene's transcript, timers or close state.
    private(set) var voice = VoiceSession()
    private(set) var definition: PracticeDefinition
    private(set) var context: PracticeContext

    private let userID: UUID
    private let onFinished: () -> Void
    private var finishing = false
    private var startCount = 0

    init(setup: PracticeSetup, userID: UUID, onFinished: @escaping () -> Void) {
        definition = setup.practice
        context = .new(for: setup, language: AppLanguage.code)
        self.userID = userID
        self.onFinished = onFinished
    }

    /// A situation the user described themselves.
    init(custom: CustomSituation, setup: PracticeSetup, userID: UUID, onFinished: @escaping () -> Void) {
        definition = custom.definition
        var context = PracticeContext.new(for: PracticeSetup(practice: custom.definition, pressure: setup.pressure, pacing: setup.pacing, persona: setup.persona, situation: custom.description), language: AppLanguage.code)
        context.custom = custom
        self.context = context
        self.userID = userID
        self.onFinished = onFinished
    }

    /// Resuming a saved attempt instead of starting a new one.
    init(draft: PracticeDraft, userID: UUID, onFinished: @escaping () -> Void) {
        definition = draft.context.custom?.definition ?? PracticeCatalog.definition(draft.context.activityId) ?? PracticeCatalog.all[0]
        context = draft.context
        self.userID = userID
        self.onFinished = onFinished
        stage = .recovery(draft)
    }

    #if DEBUG
    func loadReviewStage(_ stage: Stage) {
        self.stage = stage
        if case .live = stage { voice.loadReviewFixture() }
    }
    #endif

    /// Opening a past report: straight to its debrief.
    init(report: PracticeReport, userID: UUID, onFinished: @escaping () -> Void) {
        let activity = report.analysis.practiceContext?.activityId ?? ""
        let found = report.analysis.custom?.definition ?? PracticeCatalog.definition(activity) ?? PracticeCatalog.all[0]
        definition = found
        var context = report.analysis.practiceContext ?? PracticeContext(
            attemptId: report.id, activityId: found.id, activityVersion: found.version,
            rubricVersion: found.rubricVersion, language: AppLanguage.code, pressure: "realistic",
            pacing: "patient", situation: report.analysis.custom?.description ?? "", startedAt: ""
        )
        if let custom = report.analysis.custom { context.custom = custom }
        self.context = context
        self.userID = userID
        self.onFinished = onFinished
        stage = .report(report)
    }

    var isRetry: Bool { context.retry != nil }

    /// What every session event carries: which scene, how it was set up.
    /// Catalog ids and setup choices only, never the situation's words.
    private var eventProperties: [String: Any] {
        [
            "activity": context.isCustom ? (CustomSituation.builtIn(for: definition) != nil ? "street_hello" : "custom") : context.activityId,
            "retry": isRetry,
            "pressure": context.pressure,
            "pacing": context.pacing,
            "persona": context.personaId ?? "female",
            "language": context.language,
            "has_situation": !context.situation.isEmpty,
        ]
    }

    private func track(_ event: String, _ extra: [String: Any] = [:]) {
        Analytics.capture(event, eventProperties.merging(extra) { $1 })
    }

    // MARK: Start

    /// Retry the one moment the feedback targeted: the same question, the
    /// same scene restored, about 90 seconds. The server keeps the original
    /// setup and compares the two on that one criterion.
    func startRetry(from report: PracticeReport) async {
        guard let checkpoint = RetryCheckpoint.make(from: report), let original = report.analysis.practiceContext else { return }
        context = original
        context.attemptId = UUID()
        context.startedAt = ISO8601DateFormatter().string(from: .now)
        context.retry = checkpoint
        startCount = 0
        await start()
    }

    /// The whole scene again, from the top, with the same setup.
    func startFresh() async {
        context.attemptId = UUID()
        context.startedAt = ISO8601DateFormatter().string(from: .now)
        context.retry = nil
        startCount = 0
        await start()
    }

    func start() async {
        let startedAt = Date.now
        stage = .preparing
        finishing = false
        voice = VoiceSession()
        // Each start reserves an attempt on the server, so a retry after a
        // failed connection needs a fresh id or it's refused as a duplicate.
        startCount += 1
        if startCount > 1 {
            context.attemptId = UUID()
            context.startedAt = ISO8601DateFormatter().string(from: .now)
        }
        track("practice_started", ["attempt": startCount])
        guard await microphoneAllowed() else {
            track("practice_failed", ["reason": "microphone"])
            stage = .failed(Failure(
                title: String(localized: "Your microphone is off", bundle: AppLanguage.bundle),
                message: String(localized: "Your partner needs to hear you. Turn on the microphone for Speaking Coach in Settings.", bundle: AppLanguage.bundle),
                micDenied: true
            ))
            return
        }
        let microphoneReadyAt = Date.now
        do {
            // Catalog rehearsals start on the practice server (which checks
            // the plan and reserves the attempt); a custom situation gets its
            // token straight from the partner agent.
            let token: String
            if context.isCustom {
                token = try await CustomSituationAPI.token(persona: PracticeSetup.Persona(rawValue: context.personaId ?? "female") ?? .female)
            } else {
                let started = try await PracticeAPI.start(context)
                context = started.context
                token = started.token
                // The server counts the retry as used from this moment.
                if let parent = context.retry?.parentAttemptId { RetryLedger.mark(parent, for: userID) }
            }
            let tokenReadyAt = Date.now
            saveDraft([])
            voice.onTranscript = { [weak self] lines in self?.saveDraft(lines) }
            voice.onNaturalEnd = { [weak self] in Task { await self?.finish() } }
            voice.firstUserWords = { [weak self] in
                guard let self, !self.context.isCustom else { return }
                PracticeAPI.event("user_first_spoke", attemptId: self.context.attemptId)
            }
            try await voice.start(
                token: token,
                prompt: PracticePrompt.build(definition, context),
                firstMessage: PracticePrompt.firstMessage(definition, context),
                language: context.language,
                duration: PracticePrompt.duration(definition, context),
                maxUserTurns: context.retry == nil ? definition.maxUserTurns : 2
            )
            let roomReadyAt = Date.now
            AppLog.info("Practice startup ms: microphone \(Int(microphoneReadyAt.timeIntervalSince(startedAt) * 1000)), token \(Int(tokenReadyAt.timeIntervalSince(microphoneReadyAt) * 1000)), room \(Int(roomReadyAt.timeIntervalSince(tokenReadyAt) * 1000))")
            stage = .live
            track("practice_connected", ["startup_ms": Int(roomReadyAt.timeIntervalSince(startedAt) * 1000)])
            UIApplication.shared.isIdleTimerDisabled = true
            if !context.isCustom { PracticeAPI.event("practice_connected", attemptId: context.attemptId) }
            observeDrop()
        } catch PracticeAPIError.retryUsed {
            track("practice_failed", ["reason": "retry_used"])
            if let parent = context.retry?.parentAttemptId { RetryLedger.mark(parent, for: userID) }
            stage = .failed(Failure(
                title: String(localized: "This retry's been used", bundle: AppLanguage.bundle),
                message: PracticeAPIError.retryUsed.localizedDescription,
                canRetry: false,
                offersFresh: true
            ))
        } catch let error as PracticeAPIError {
            // A refusal (409) won't change on a second ask; only a dropped
            // connection or a busy server might.
            let refused: Bool = if case .server(409, _) = error { true } else { false }
            track("practice_failed", ["reason": error.isSubscription ? "subscription" : refused ? "refused" : "server"])
            stage = .failed(Failure(title: String(localized: "Couldn't start", bundle: AppLanguage.bundle), message: error.localizedDescription, canRetry: !error.isSubscription && !refused))
        } catch {
            track("practice_failed", ["reason": "connection"])
            stage = .failed(Failure(title: String(localized: "Couldn't connect", bundle: AppLanguage.bundle), message: String(localized: "Your partner couldn't connect. Check your connection and try again.", bundle: AppLanguage.bundle)))
        }
    }

    private func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    /// If the line drops on its own mid-scene, keep what was said: go
    /// straight to feedback when there are words, offer a retry when not.
    private func observeDrop() {
        Task { [weak self] in
            while let self, self.stage == .live {
                if self.voice.phase == .ended, self.voice.droppedUnexpectedly {
                    await self.finish()
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: Finish

    /// Ends the scene and asks for feedback on what was said.
    func finish() async {
        guard !finishing, stage == .live else { return }
        finishing = true
        UIApplication.shared.isIdleTimerDisabled = false
        let transcript = voice.transcript
        await voice.end()
        if !context.isCustom { PracticeAPI.event("practice_ended", attemptId: context.attemptId) }
        let draft = PracticeDraft(context: context, transcript: transcript)
        saveDraft(transcript)
        track("practice_ended", [
            "user_turns": transcript.filter { $0.role == .user }.count,
            "dropped": voice.droppedUnexpectedly,
        ])
        guard draft.hasUserWords else {
            stage = .failed(Failure(
                title: String(localized: "No answer yet", bundle: AppLanguage.bundle),
                message: String(localized: "Your partner didn't hear you answer, so there's nothing to give feedback on. Try again when you're ready.", bundle: AppLanguage.bundle)
            ))
            return
        }
        await assess(draft)
    }

    func assess(_ draft: PracticeDraft) async {
        stage = .assessing
        do {
            let report: PracticeReport
            if draft.context.isCustom, let custom = draft.context.custom {
                let analysis = try await CustomSituationAPI.analyze(draft.transcript, situation: custom, language: draft.context.language)
                report = try await CustomSituationAPI.save(analysis, transcript: draft.transcript, context: draft.context, userID: userID)
            } else {
                report = try await PracticeAPI.assess(attemptId: draft.context.attemptId, transcript: draft.transcript)
            }
            PracticeDrafts.clear(userID: userID)
            stage = .report(report)
            Haptics.success()
            var result: [String: Any] = [:]
            if let assessment = report.analysis.practice {
                result["criteria_clear"] = assessment.criteria.filter { $0.level == 2 }.count
                result["criteria_partly"] = assessment.criteria.filter { $0.level == 1 }.count
                result["criteria_count"] = assessment.criteria.count
            }
            if let score = report.analysis.score { result["score"] = min(max(score, 0), 100) }
            if let comparison = RetryComparison(report: report) { result["retry_change"] = comparison.change }
            track("feedback_shown", result)
            if !draft.context.isCustom { PracticeAPI.event("debrief_viewed", attemptId: draft.context.attemptId) }
            onFinished()
        } catch {
            track("feedback_failed")
            stage = .failed(Failure(
                title: String(localized: "Feedback didn't finish", bundle: AppLanguage.bundle),
                message: (error as? LocalizedError)?.errorDescription ?? String(localized: "Your words are saved. Try again in a moment.", bundle: AppLanguage.bundle),
                canAssess: true,
                canRetry: false
            ))
        }
    }

    /// Retry feedback for the saved words after a failure.
    func retryAssessment() async {
        guard let draft = PracticeDrafts.load(userID: userID) else { return }
        await assess(draft)
    }

    func discardDraft() {
        PracticeDrafts.clear(userID: userID)
    }

    /// Leaving mid-scene: stop the microphone, keep the words.
    func abandon() async {
        UIApplication.shared.isIdleTimerDisabled = false
        if stage == .live { track("practice_left", ["user_turns": voice.userTurns]) }
        if voice.phase == .live || voice.phase == .connecting { await voice.end() }
        if !voice.transcript.contains(where: { $0.role == .user }) {
            PracticeDrafts.clear(userID: userID)
        }
    }

    private func saveDraft(_ transcript: [TranscriptLine]) {
        PracticeDrafts.save(PracticeDraft(context: context, transcript: transcript), userID: userID)
    }
}

private extension PracticeAPIError {
    var isSubscription: Bool {
        if case .subscriptionRequired = self { return true }
        return false
    }
}
