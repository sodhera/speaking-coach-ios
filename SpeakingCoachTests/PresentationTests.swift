import XCTest
@testable import SpeakingCoach

final class PresentationTests: XCTestCase {
    private func rehearsal(transcript: String = "", durationMs: Int = 60_000) -> PresentationRehearsal {
        PresentationRehearsal(
            id: UUID(), deckID: UUID(), startedAt: .now, durationMs: durationMs, audioFile: "a.m4a",
            transcript: transcript,
            slideEvents: [SlideEvent(slideIndex: 0, atMs: 0), SlideEvent(slideIndex: 1, atMs: 10_000), SlideEvent(slideIndex: 3, atMs: 30_000)],
            questions: [], answers: []
        )
    }

    func testReplayFollowsTheSlidesAsTheyWereShown() {
        let talk = rehearsal()
        XCTAssertEqual(talk.slide(atMs: 0), 0)
        XCTAssertEqual(talk.slide(atMs: 9_999), 0)
        XCTAssertEqual(talk.slide(atMs: 10_000), 1)
        XCTAssertEqual(talk.slide(atMs: 45_000), 3)
    }

    /// The server's schema requires `slideIndex` present, even when null.
    func testQuestionsAlwaysSendSlideIndex() throws {
        let question = AudienceQuestion(id: "q", question: "Why?", reason: "Tests it.", slideIndex: nil)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(question), encoding: .utf8))
        XCTAssertTrue(json.contains("\"slideIndex\":null"), json)
    }

    func testBriefMatchesTheServersQuestionStyles() throws {
        let brief = PresentationBrief(audience: "", purpose: "", instructions: "", questionStyle: .challenging)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(brief), encoding: .utf8))
        XCTAssertTrue(json.contains("\"questionStyle\":\"challenging\""))
        XCTAssertEqual(PresentationBrief.QuestionStyle.allCases.map(\.rawValue), ["supportive", "curious", "challenging"])
    }

    func testPaceIsWordsPerMinute() {
        let words = Array(repeating: "word", count: 150).joined(separator: " ")
        XCTAssertEqual(RehearsalReviewView.wordsPerMinute(rehearsal(transcript: words, durationMs: 60_000)), 150)
        XCTAssertEqual(RehearsalReviewView.wordsPerMinute(rehearsal(transcript: words, durationMs: 120_000)), 75)
    }
}
