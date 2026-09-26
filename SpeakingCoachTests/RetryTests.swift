import XCTest
@testable import SpeakingCoach

/// The retry checkpoint must match the server's `retryFromReport`, or the app
/// would offer retries the server refuses.
final class RetryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLanguage.choose("en")
    }

    private let practice = PracticeCatalog.definition("interview_tell_me_about_yourself")!

    private func report(evidenceTurn: String?, retry: RetryCheckpoint? = nil, transcript: [TranscriptLine]? = nil, target: Int = 1) -> PracticeReport {
        var context = PracticeContext.new(for: PracticeSetup(practice: practice, pressure: .realistic, persona: .female), language: "en")
        context.retry = retry
        let lines = transcript ?? [
            TranscriptLine(id: "coach-1", role: .coach, text: "Tell me about yourself."),
            TranscriptLine(id: "user-1", role: .user, text: "I'm a designer."),
            TranscriptLine(id: "coach-2", role: .coach, text: "Why this role?"),
            TranscriptLine(id: "user-2", role: .user, text: "I like the product."),
        ]
        let criteria = practice.criteria.enumerated().map { index, criterion in
            CriterionResult(
                id: criterion.id, level: index == target ? 1 : 2, note: "",
                evidence: index == target ? evidenceTurn.map { [.init(turnId: $0, quote: "I like the product")] } ?? [] : []
            )
        }
        let assessment = PracticeAssessment(summary: "", criteria: criteria, adjustment: "", targetCriterionId: practice.criteria[target].id, limitations: [])
        return PracticeReport(id: context.attemptId, transcript: lines, analysis: .init(score: 50, summary: nil, practice: assessment, practiceContext: context))
    }

    func testRetryReturnsToTheQuestionBeforeTheQuotedAnswer() throws {
        let checkpoint = try XCTUnwrap(RetryCheckpoint.make(from: report(evidenceTurn: "user-2")))
        XCTAssertEqual(checkpoint.prompt, "Why this role?")
        XCTAssertEqual(checkpoint.context.map(\.id), ["coach-1", "user-1"])
        XCTAssertEqual(checkpoint.criterionId, practice.criteria[1].id)
        XCTAssertEqual(checkpoint.previous.level, 1)
    }

    func testWithoutEvidenceItFallsBackToTheFirstAnswer() throws {
        let checkpoint = try XCTUnwrap(RetryCheckpoint.make(from: report(evidenceTurn: nil)))
        XCTAssertEqual(checkpoint.prompt, "Tell me about yourself.")
        XCTAssertTrue(checkpoint.context.isEmpty)
    }

    func testARetryCannotBeRetried() {
        let previous = CriterionResult(id: "x", level: 0, note: "", evidence: [])
        let retry = RetryCheckpoint(parentAttemptId: UUID(), prompt: "Q", context: [], criterionId: "x", previous: previous)
        XCTAssertNil(RetryCheckpoint.make(from: report(evidenceTurn: "user-2", retry: retry)))
    }

    func testNoQuestionBeforeTheAnswerMeansNoRetry() {
        let lines = [TranscriptLine(id: "user-1", role: .user, text: "Hi")]
        XCTAssertNil(RetryCheckpoint.make(from: report(evidenceTurn: nil, transcript: lines)))
    }

    func testOlderReportsWithoutAnAssessmentCannotBeRetried() {
        let old = PracticeReport(id: UUID(), transcript: [], analysis: .init(score: 40, summary: "Old", improvements: ["x"]))
        XCTAssertNil(RetryCheckpoint.make(from: old))
    }

    func testComparisonReadsTheTargetedCriterion() throws {
        let previous = CriterionResult(id: practice.criteria[1].id, level: 1, note: "", evidence: [])
        let retry = RetryCheckpoint(parentAttemptId: UUID(), prompt: "Why this role?", context: [], criterionId: practice.criteria[1].id, previous: previous)
        var retried = report(evidenceTurn: "user-2", retry: retry)
        retried.analysis.practice?.criteria[1].level = 2
        let comparison = try XCTUnwrap(RetryComparison(report: retried))
        XCTAssertEqual(comparison.change, 1)
        XCTAssertNil(RetryComparison(report: report(evidenceTurn: "user-2")), "A first attempt has nothing to compare against")
    }
}
