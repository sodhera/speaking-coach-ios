import XCTest
@testable import SpeakingCoach

final class CustomSituationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLanguage.choose("en")
    }

    private let situation = CustomSituation(description: "Ask my landlord to return my deposit by Friday.", partner: "My landlord", title: "Talking to my landlord")

    func testDefinitionCarriesTheUsersOwnWords() {
        let definition = situation.definition
        XCTAssertEqual(definition.partner, "My landlord")
        XCTAssertEqual(definition.objective, situation.description)
        XCTAssertTrue(definition.opening.isEmpty, "A custom partner sets the scene itself")
    }

    func testPromptLetsThePartnerOpenTheSceneItself() {
        let setup = PracticeSetup(practice: situation.definition, pressure: .realistic, persona: .female, situation: situation.description)
        var context = PracticeContext.new(for: setup, language: "en")
        context.custom = situation
        let prompt = PracticePrompt.build(situation.definition, context)
        XCTAssertTrue(prompt.contains("open the scene in character"))
        XCTAssertFalse(prompt.contains("open with exactly:"))
        XCTAssertTrue(prompt.contains("My landlord"))
        XCTAssertTrue(context.isCustom)
    }

    func testCustomReportsRoundTripWithTheirSituation() throws {
        let report = PracticeReport(id: UUID(), transcript: [], analysis: .init(
            score: 58, summary: "S", improvements: ["a"], subscores: [Subscore(label: "Clarity", score: 64, note: "n")],
            rewrites: [Rewrite(original: "o", better: "b")], custom: situation
        ))
        let decoded = try JSONDecoder().decode(PracticeReport.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(decoded.analysis.custom, situation)
        XCTAssertNil(RetryCheckpoint.make(from: decoded), "Custom situations have no rubric to retry against")
    }

    func testTitleReadsNaturally() {
        XCTAssertEqual(CustomSituationView.title(for: "my landlord"), "My landlord")
    }

    func testBandsAreWordsNotNumbers() {
        XCTAssertEqual(DebriefView.band(80), "Strong")
        XCTAssertEqual(DebriefView.band(60), "Getting there")
        XCTAssertEqual(DebriefView.band(30), "Needs work")
    }
}
