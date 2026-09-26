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
              let criterion = assessment.criteria.first(where: { $0.id == assessment.targetCriterionId }),
              let questionIndex = questionIndex(for: criterion, in: report.transcript)
        else { return nil }
        let transcript = report.transcript
        return RetryCheckpoint(
            parentAttemptId: context.attemptId,
            prompt: transcript[questionIndex].text,
            context: Array(transcript[..<questionIndex].suffix(8)),
            criterionId: criterion.id,
            previous: criterion
        )
    }

    /// Where the moment sits in a transcript: the partner's question just
    /// before the answer a criterion's feedback quotes (or, with no quote,
    /// the first answer). The debrief marks this same line in the
    /// conversation.
    static func questionIndex(for criterion: CriterionResult, in transcript: [TranscriptLine]) -> Int? {
        let answerIndex: Int? = {
            if let turnId = criterion.evidence.first?.turnId {
                return transcript.firstIndex { $0.id == turnId && $0.role == .user }
            }
            return transcript.firstIndex { $0.role == .user }
        }()
        guard let answerIndex else { return nil }
        return transcript[..<answerIndex].lastIndex { $0.role == .coach }
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
    /// A short title for history: who it was with, e.g. "My landlord".
    var title: String

    /// A rehearsal definition the room and prompt can run, built from the
    /// user's own words rather than the catalog.
    var definition: PracticeDefinition {
        if self == .streetHello { return Self.streetHelloDefinition }
        return PracticeDefinition(
            id: "custom", version: 1, rubricVersion: "custom-v1", scenarioId: "custom",
            title: title, category: "custom", format: "rehearsal", durationMinutes: 4,
            partner: partner, objective: description, opening: "",
            criteria: [], beats: [
                "Open the scene naturally, in character, with one short line that sets it up.",
                "React to what they actually say; push back once if it's realistic.",
                "Close naturally in one sentence.",
            ],
            scaffold: String(localized: "Start with what you want: “I'd like to talk about…”", bundle: AppLanguage.bundle),
            transfer: String(localized: "Say your first line out loud once more before the real conversation.", bundle: AppLanguage.bundle),
            maxUserTurns: 4,
            recovery: ["If they get stuck, ask a simpler version of your last question."],
            variants: []
        )
    }
}

// MARK: - Built-in scenes

extension CustomSituation {
    /// Impromptu: someone friendly stops you on the street and starts
    /// talking. No warning and no script; the skill is answering before you
    /// freeze, warmly, and handing the conversation back. The catalog has no
    /// scene like it, so it runs on the custom-situation endpoints.
    static var streetHello: CustomSituation {
        CustomSituation(
            description: CatalogText.text("A friendly stranger stops me on the street and starts a conversation out of nowhere. I want to answer quickly and warmly instead of freezing, and keep it going for a minute."),
            partner: CatalogText.text("Someone on the street"),
            title: CatalogText.text("A stranger says hi")
        )
    }

    /// Marks a definition as a built-in scene, since every custom definition
    /// shares the id "custom" and titles change with the language.
    private static let streetHelloScenario = "street_hello"

    /// The built-in scene a definition was made from, if any. Built-in
    /// scenes start through the custom path, never `/api/practice/start`.
    static func builtIn(for definition: PracticeDefinition) -> CustomSituation? {
        definition.id == "custom" && definition.scenarioId == streetHelloScenario ? .streetHello : nil
    }

    fileprivate static var streetHelloDefinition: PracticeDefinition {
        PracticeDefinition(
            id: "custom", version: 1, rubricVersion: "custom-v1", scenarioId: streetHelloScenario,
            title: streetHello.title, category: "custom", format: "rehearsal", durationMinutes: 2,
            partner: streetHello.partner,
            objective: CatalogText.text("Answer before you freeze, keep it warm, and hand the conversation back with a question."),
            opening: CatalogText.text("Hey, sorry, random question. Is that café over there any good? You look like you'd know."),
            criteria: [],
            beats: [
                "Open cold and friendly, as a stranger who just stopped them, with one light question.",
                "React to what they say, then share one small thing about yourself.",
                "If they go quiet for more than a few seconds, nudge kindly: “Sorry, did I catch you at a bad time?”",
                "Wrap up naturally after a minute: “Anyway, I'll let you go. Nice chatting!”",
            ],
            scaffold: CatalogText.text("Answer, then hand it back: “It's great, actually. Are you new around here?”"),
            transfer: CatalogText.text("Next time a stranger says hi, answer first and think second. A short warm reply beats a perfect one."),
            maxUserTurns: 4,
            recovery: ["If they stall, ask something even simpler about the street or the weather."],
            variants: [],
            openingLanguage: CatalogText.isTranslated("Hey, sorry, random question. Is that café over there any good? You look like you'd know.") ? AppLanguage.code : "en"
        )
    }
}

/// What survives a crash, a dropped call or a killed app: enough to ask for
/// feedback on the words already spoken.
struct PracticeDraft: Codable, Equatable {
    var context: PracticeContext
    var transcript: [TranscriptLine]

    var hasUserWords: Bool { transcript.contains { $0.role == .user } }
}
