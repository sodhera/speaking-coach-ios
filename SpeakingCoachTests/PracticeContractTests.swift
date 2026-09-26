import XCTest
@testable import SpeakingCoach

/// The practice endpoints are shared with the server, so these pin the wire
/// shapes and the partner prompt's non-negotiables.
final class PracticeContractTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLanguage.choose("en")
    }

    private var definition: PracticeDefinition { PracticeCatalog.definition("interview_tell_me_about_yourself")! }

    func testReportDecodesTheServersShape() throws {
        let json = """
        {"id":"6f1c2b7a-1d2e-4f5a-9b8c-0a1b2c3d4e5f","user_id":"x","persona_id":"female","scenario_id":"job_interview",
         "transcript":[{"id":"coach-a","role":"coach","text":"Tell me about yourself."},{"id":"user-b","role":"user","text":"I design tools.","eventId":3}],
         "analysis":{"score":67,"summary":"Clear start.","subscores":[],"improvements":["x"],"rewrites":[],
           "practice":{"summary":"Clear start.","criteria":[{"id":"c1","level":2,"note":"Good.","evidence":[{"turnId":"user-b","quote":"I design tools."}]}],
             "adjustment":"Add one result.","targetCriterionId":"c1","limitations":[],"rubricVersion":"real-life-v1"},
           "practiceContext":{"attemptId":"6f1c2b7a-1d2e-4f5a-9b8c-0a1b2c3d4e5f","activityId":"interview_tell_me_about_yourself","activityVersion":1,
             "rubricVersion":"real-life-v1","language":"en","pressure":"realistic","pacing":"patient","situation":"","startedAt":"2026-09-23T10:00:00.000Z","personaId":"female"}},
         "score":67,"created_at":"2026-09-23T10:05:00Z"}
        """
        let report = try JSONDecoder().decode(PracticeReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.transcript.count, 2)
        XCTAssertEqual(report.analysis.practice?.criteria.first?.evidence.first?.quote, "I design tools.")
        XCTAssertEqual(report.analysis.practiceContext?.activityId, "interview_tell_me_about_yourself")
    }

    func testOlderReportsWithoutPracticeStillDecode() throws {
        let json = #"{"id":"6f1c2b7a-1d2e-4f5a-9b8c-0a1b2c3d4e5f","transcript":[],"analysis":{"score":40,"summary":"Old."}}"#
        let report = try JSONDecoder().decode(PracticeReport.self, from: Data(json.utf8))
        XCTAssertNil(report.analysis.practice)
        XCTAssertEqual(report.analysis.summary, "Old.")
    }

    func testPromptCarriesTheOpeningAndTheControlContract() {
        let setup = PracticeSetup(practice: definition, pressure: .challenging, persona: .male)
        let prompt = PracticePrompt.build(definition, PracticeContext.new(for: setup, language: "es"))
        XCTAssertTrue(prompt.contains(definition.opening))
        XCTAssertTrue(prompt.contains(PracticePrompt.beginSignal))
        XCTAssertTrue(prompt.contains(PracticePrompt.resumeSignal))
        XCTAssertTrue(prompt.contains("\"es\""))
        XCTAssertTrue(prompt.contains("Never score"))
        XCTAssertTrue(prompt.contains("Push back"))
    }

    func testControlSignalsNeverCountAsWords() {
        XCTAssertTrue(PracticePrompt.isControlSignal(PracticePrompt.beginSignal))
        XCTAssertTrue(PracticePrompt.isControlSignal("  \(PracticePrompt.resumeSignal) "))
        XCTAssertFalse(PracticePrompt.isControlSignal("I led the redesign."))
    }

    func testRetryShortensTheSceneAndOpensOnTheCheckpoint() {
        let setup = PracticeSetup(practice: definition, pressure: .realistic, persona: .female)
        var context = PracticeContext.new(for: setup, language: "en")
        context.retry = RetryCheckpoint(
            parentAttemptId: UUID(), prompt: "Why this role?", context: [],
            criterionId: "c1", previous: CriterionResult(id: "c1", level: 1, note: "", evidence: [])
        )
        XCTAssertEqual(PracticePrompt.duration(definition, context), 90)
        XCTAssertEqual(PracticePrompt.firstMessage(definition, context), "Why this role?")
        XCTAssertTrue(PracticePrompt.build(definition, context).contains("Your first line is supplied when the conversation connects: Why this role?"))
    }

    func testNewContextMatchesTheSetup() {
        let setup = PracticeSetup(practice: definition, pressure: .supportive, pacing: .normal, persona: .male, situation: "Startup")
        let context = PracticeContext.new(for: setup, language: "fr")
        XCTAssertEqual(context.activityId, definition.id)
        XCTAssertEqual(context.activityVersion, definition.version)
        XCTAssertEqual(context.pressure, "supportive")
        XCTAssertEqual(context.pacing, "normal")
        XCTAssertEqual(context.personaId, "male")
        XCTAssertEqual(context.language, "fr")
    }

    func testDraftKnowsWhetherWordsWereSpoken() {
        let setup = PracticeSetup(practice: definition, pressure: .realistic, persona: .female)
        var draft = PracticeDraft(context: .new(for: setup, language: "en"), transcript: [TranscriptLine(id: "coach-1", role: .coach, text: "Hi")])
        XCTAssertFalse(draft.hasUserWords)
        draft.transcript.append(TranscriptLine(id: "user-1", role: .user, text: "Hello"))
        XCTAssertTrue(draft.hasUserWords)
    }

    func testEveryAppLanguageIsSpokenByThePartner() {
        for code in AppLanguage.supported {
            XCTAssertNotNil(ElevenLabsLanguageCheck.supports(code), "\(code) isn't a partner language")
        }
    }

    func testEveryAppLanguageShipsItsStrings() {
        for code in AppLanguage.supported {
            XCTAssertNotNil(Bundle.main.path(forResource: AppLanguage.localization(for: code), ofType: "lproj"), code)
            XCTAssertNotEqual(AppLanguage.string("Choose your language", in: code), code == "en" ? "" : "Choose your language", code)
        }
    }
}
