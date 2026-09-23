import XCTest
@testable import SpeakingCoach

final class OnboardingLogicTests: XCTestCase {
    func testNoAgreementMeansSteadyNeverAProblem() {
        XCTAssertEqual(SpeakingPattern.from([:]), .steady)
        let allNo = Dictionary(uniqueKeysWithValues: PainStatement.allCases.map { ($0, Agreement.no) })
        XCTAssertEqual(SpeakingPattern.from(allNo), .steady)
    }

    func testOnlyInMyHeadAloneDoesNotAssignAPattern() {
        XCTAssertEqual(SpeakingPattern.from([.onlyInMyHead: .yes]), .steady)
    }

    func testStrongestPatternWins() {
        let answers: [PainStatement: Agreement] = [
            .rambleWhenNervous: .yes, .stayQuiet: .sometimes, .wordsVanish: .no,
        ]
        XCTAssertEqual(SpeakingPattern.from(answers), .rambler)
    }

    func testBlankOutAccumulatesAcrossItsTwoStatements() {
        let answers: [PainStatement: Agreement] = [
            .wordsVanish: .sometimes, .blankOnTheSpot: .sometimes, .rambleWhenNervous: .sometimes,
        ]
        XCTAssertEqual(SpeakingPattern.from(answers), .blankOut)
    }

    func testTiesBreakInDeckOrder() {
        let answers: [PainStatement: Agreement] = [.stayQuiet: .yes, .replayAfterwards: .yes]
        XCTAssertEqual(SpeakingPattern.from(answers), .holdBack)
    }

    func testEveryMomentMapsToARealCatalogPractice() {
        for moment in SpeakingMoment.allCases {
            XCTAssertNotNil(PracticeCatalog.definition(moment.firstPracticeID), "\(moment) → \(moment.firstPracticeID)")
        }
    }

    func testCatalogDecodesAllThirteenPractices() {
        XCTAssertEqual(PracticeCatalog.all.count, 13)
    }

    func testEveryQuizHasAValidBestAnswer() {
        for moment in SpeakingMoment.allCases {
            let quiz = OpeningQuiz.for(moment)
            XCTAssertEqual(quiz.options.count, 3)
            XCTAssertTrue(quiz.options.indices.contains(quiz.bestIndex))
        }
    }

    func testUntouchedReadinessIsNotRecorded() {
        var answers = OnboardingAnswers()
        answers.name = "  Sulav "
        XCTAssertNil(answers.profile().readiness)
        XCTAssertEqual(answers.profile().name, "Sulav")
        answers.readinessTouched = true
        answers.readiness = 3
        XCTAssertEqual(answers.profile().readiness, 3)
    }

    func testProfileRoundTripsThroughJSON() throws {
        var answers = OnboardingAnswers()
        answers.name = "Sulav"
        answers.moment = .raise
        answers.statements = [.stayQuiet: .yes]
        answers.costs = [.creditForIdeas]
        answers.outcomes = [.getTheYes]
        let profile = answers.profile(at: Date(timeIntervalSince1970: 1_800_000_000))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CoachProfile.self, from: encoder.encode(profile))
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.pattern, .holdBack)
    }

    func testGeneralImprovementHasItsOwnCopyEverywhere() {
        let moment = SpeakingMoment.everyday
        XCTAssertTrue(moment.isGeneral)
        XCTAssertNotNil(PracticeCatalog.definition(moment.firstPracticeID))
        XCTAssertFalse(moment.readinessQuestion.contains("everyday conversations right now"))
        XCTAssertEqual(OpeningQuiz.for(moment).options.count, 3)
        XCTAssertFalse(SpeakingMoment.interview.isGeneral)
    }
}
