import Foundation

/// The server's view of one attempt — what `/api/practice/start` returns and
/// what later calls refer back to. Field names match the server exactly.
struct PracticeContext: Codable, Equatable {
    var attemptId: UUID
    var activityId: String
    var activityVersion: Int
    var rubricVersion: String
    var language: String
    var pressure: String
    var pacing: String
    var situation: String
    var startedAt: String
    var personaId: String?
    var retry: RetryCheckpoint?
    /// Set only for a custom situation — who the partner plays and what the
    /// user wants to say. Never sent to the practice server.
    var custom: CustomSituation?

    var isCustom: Bool { custom != nil }

    static func new(for setup: PracticeSetup, language: String) -> PracticeContext {
        PracticeContext(
            attemptId: UUID(),
            activityId: setup.practice.id,
            activityVersion: setup.practice.version,
            rubricVersion: setup.practice.rubricVersion,
            language: language,
            pressure: setup.pressure.rawValue,
            pacing: setup.pacing.rawValue,
            situation: setup.situation,
            startedAt: ISO8601DateFormatter().string(from: .now),
            personaId: setup.persona.rawValue
        )
    }
}

/// A focused retry: the one question to answer again, with the moments
/// before it restored.
struct RetryCheckpoint: Codable, Equatable {
    var parentAttemptId: UUID
    var prompt: String
    var context: [TranscriptLine]
    var criterionId: String
    var previous: CriterionResult

    /// The moment to retry, from a finished report: the question the partner
    /// asked just before the answer the feedback targeted, with up to eight
    /// lines of what came before it. Nil when the report can't be retried —
    /// no assessment, already a retry, or no question to return to. Mirrors
    /// the server's own `retryFromReport`, so what the app offers is what the
    /// server accepts.
    static func make(from report: PracticeReport) -> RetryCheckpoint? {
        guard let assessment = report.analysis.practice,
              let context = report.analysis.practiceContext,
              context.retry == nil,
              let criterion = assessment.criteria.first(where: { $0.id == assessment.targetCriterionId })
        else { return nil }
        let transcript = report.transcript
        let answerIndex: Int? = {
            if let turnId = criterion.evidence.first?.turnId {
                return transcript.firstIndex { $0.id == turnId && $0.role == .user }
            }
            return transcript.firstIndex { $0.role == .user }
        }()
        guard let answerIndex else { return nil }
        guard let questionIndex = transcript[..<answerIndex].lastIndex(where: { $0.role == .coach }) else { return nil }
        return RetryCheckpoint(
            parentAttemptId: context.attemptId,
            prompt: transcript[questionIndex].text,
            context: Array(transcript[..<questionIndex].suffix(8)),
            criterionId: criterion.id,
            previous: criterion
        )
    }
}

/// Before and after on the one criterion a retry targeted — only when the
/// rubric is the same, so the two levels mean the same thing.
struct RetryComparison: Equatable {
    let before: CriterionResult
    let after: CriterionResult
    var change: Int { after.level - before.level }

    init?(report: PracticeReport) {
        guard let retry = report.analysis.practiceContext?.retry,
              let assessment = report.analysis.practice,
              let after = assessment.criteria.first(where: { $0.id == retry.criterionId }),
              assessment.rubricVersion == nil || assessment.rubricVersion == report.analysis.practiceContext?.rubricVersion
        else { return nil }
        before = retry.previous
        self.after = after
    }
}

/// One line of the conversation, in the shape the assessment endpoint takes.
struct TranscriptLine: Codable, Equatable, Identifiable {
    enum Role: String, Codable { case user, coach }
    var id: String
    var role: Role
    var text: String
}

// MARK: - Assessment

struct CriterionResult: Codable, Equatable {
    struct Evidence: Codable, Equatable {
        var turnId: String
        var quote: String
    }

    var id: String
    /// 0 not yet observed, 1 partly, 2 clearly demonstrated.
    var level: Int
    var note: String
    var evidence: [Evidence]
}

struct PracticeAssessment: Codable, Equatable {
    var rubricVersion: String?
    var summary: String
    var criteria: [CriterionResult]
    var adjustment: String
    var targetCriterionId: String
    var limitations: [String]
}

/// A saved `reports` row, as `/api/practice/:id/assess` returns it.
struct PracticeReport: Codable, Equatable {
    struct Analysis: Codable, Equatable {
        var score: Int?
        var summary: String?
        /// Custom situations and older reports carry these instead of a
        /// practice assessment.
        var improvements: [String]?
        var subscores: [Subscore]?
        var rewrites: [Rewrite]?
        /// Set on custom-situation reports.
        var custom: CustomSituation?
        var practice: PracticeAssessment?
        var practiceContext: PracticeContext?
    }

    var id: UUID
    var transcript: [TranscriptLine]
    var analysis: Analysis
}

struct Subscore: Codable, Equatable {
    var label: String
    var score: Int
    var note: String
}

struct Rewrite: Codable, Equatable {
    var original: String
    var better: String
}

/// A conversation the user described themselves.
struct CustomSituation: Codable, Equatable {
    /// What they need to say, in their words.
    var description: String
    /// Who the partner plays — "my landlord", "a new manager".
    var partner: String
    /// A short title for history, e.g. "Talking to my landlord".
    var title: String

    /// A rehearsal definition the room and prompt can run, built from the
    /// user's own words rather than the catalog.
    var definition: PracticeDefinition {
        if self == .ieltsSpeaking { return Self.ieltsDefinition }
        return PracticeDefinition(
            id: "custom", version: 1, rubricVersion: "custom-v1", scenarioId: "custom",
            title: title, category: "custom", format: "rehearsal", durationMinutes: 4,
            partner: partner, objective: description, opening: "",
            criteria: [], beats: [
                "Open the scene naturally, in character, with one short line that sets it up.",
                "React to what they actually say; push back once if it's realistic.",
                "Close naturally in one sentence.",
            ],
            scaffold: "Start with what you want: “I'd like to talk about…”",
            transfer: "Say your first line out loud once more before the real conversation.",
            maxUserTurns: 4,
            recovery: ["If they get stuck, ask a simpler version of your last question."],
            variants: []
        )
    }
}

// MARK: - Built-in scenes

extension CustomSituation {
    /// IELTS Speaking Part 1, played by an examiner. Built into the app until
    /// the server's catalog has IELTS rehearsals of its own: it runs on the
    /// custom-situation endpoints, so the debrief is the general one, not a
    /// band score.
    static let ieltsSpeaking = CustomSituation(
        description: "I'm preparing for the IELTS Speaking test. Play the examiner for Part 1: ask short questions about familiar topics (my home, my work or studies, my free time), one at a time, the way the real test does.",
        partner: "An IELTS Speaking examiner",
        title: "IELTS Speaking · Part 1"
    )

    /// The built-in scene a definition was made from, if any. Built-in
    /// scenes start through the custom path, never `/api/practice/start`.
    static func builtIn(for definition: PracticeDefinition) -> CustomSituation? {
        guard definition.id == "custom" else { return nil }
        return [CustomSituation.ieltsSpeaking].first { $0.title == definition.title }
    }

    fileprivate static let ieltsDefinition = PracticeDefinition(
        id: "custom", version: 1, rubricVersion: "custom-v1", scenarioId: "custom",
        title: ieltsSpeaking.title, category: "custom", format: "rehearsal", durationMinutes: 4,
        partner: ieltsSpeaking.partner,
        objective: "Answer the examiner's Part 1 questions in full: answer, then extend with a reason or an example.",
        opening: "Good morning. My name is Alex, and I'll be your examiner today. Can you tell me your full name, please?",
        criteria: [],
        beats: [
            "Ask for their full name, then where they're from.",
            "Ask two or three short questions on one familiar topic: work or studies, home, or free time.",
            "Move to a second familiar topic with two short questions.",
            "Close as the examiner does: “Thank you. That's the end of Part 1.”",
        ],
        scaffold: "Answer, then add why: “Yes, I really enjoy it, because…”",
        transfer: "In the test, give every answer a reason or an example — never just yes or no.",
        maxUserTurns: 7,
        recovery: ["If they stall, repeat the question once, slowly, exactly as an examiner would. Never help with the answer."],
        variants: []
    )
}

/// What survives a crash, a dropped call or a killed app: enough to ask for
/// feedback on the words already spoken.
struct PracticeDraft: Codable, Equatable {
    var context: PracticeContext
    var transcript: [TranscriptLine]

    var hasUserWords: Bool { transcript.contains { $0.role == .user } }
}
