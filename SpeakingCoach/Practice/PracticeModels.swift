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
        /// Older reports (before the practice assessment) carry these instead.
        var improvements: [String]?
        var practice: PracticeAssessment?
        var practiceContext: PracticeContext?
    }

    var id: UUID
    var transcript: [TranscriptLine]
    var analysis: Analysis
}

/// What survives a crash, a dropped call or a killed app: enough to ask for
/// feedback on the words already spoken.
struct PracticeDraft: Codable, Equatable {
    var context: PracticeContext
    var transcript: [TranscriptLine]

    var hasUserWords: Bool { transcript.contains { $0.role == .user } }
}
