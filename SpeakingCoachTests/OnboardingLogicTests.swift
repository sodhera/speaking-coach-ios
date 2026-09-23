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

    func testEveryMomentHasAFirstPractice() {
        for moment in SpeakingMoment.allCases {
            let practice = moment.firstPractice
            XCTAssertNotNil(practice, "\(moment)")
            // Catalog moments must name a real catalog rehearsal; built-in
            // ones must route back to their own scene.
            if let situation = moment.builtInSituation {
                XCTAssertEqual(practice.flatMap(CustomSituation.builtIn(for:)), situation)
            } else {
                XCTAssertNotNil(PracticeCatalog.definition(practice?.id ?? ""), "\(moment)")
            }
        }
    }

    func testEveryMomentBelongsToExactlyOneCategory() {
        for moment in SpeakingMoment.allCases {
            XCTAssertEqual(SpeakingCategory.allCases.filter { $0.moments.contains(moment) }.count, 1, "\(moment)")
        }
    }

    func testIELTSIsOnlyOfferedForEnglish() {
        XCTAssertTrue(SpeakingCategory.available(forPracticeLanguage: "en").contains(.ielts))
        XCTAssertFalse(SpeakingCategory.available(forPracticeLanguage: "de").contains(.ielts))
        XCTAssertEqual(SpeakingCategory.available(forPracticeLanguage: "de").count, 3)
    }

    func testCatalogRehearsalsAreNeverMistakenForBuiltInScenes() {
        for practice in PracticeCatalog.all {
            XCTAssertNil(CustomSituation.builtIn(for: practice), practice.id)
        }
        let userScene = CustomSituation(description: "My landlord owes me a deposit.", partner: "my landlord", title: "Talking to my landlord")
        XCTAssertNil(CustomSituation.builtIn(for: userScene.definition))
    }

    func testIELTSExaminerOpensLikeTheRealTest() {
        let practice = SpeakingMoment.ielts.firstPractice
        XCTAssertEqual(practice?.id, "custom")
        XCTAssertTrue(practice?.opening.contains("full name") ?? false)
    }

    func testCatalogDecodesAllThirteenPractices() {
        XCTAssertEqual(PracticeCatalog.all.count, 13)
    }

    func testEveryDemoHasFillersToLiftAndACleanRetry() {
        for moment in SpeakingMoment.allCases {
            let script = DemoScript.for(moment)
            XCTAssertGreaterThan(script.fillerCount, 0, "\(moment)")
            XCTAssertTrue(script.firstWords.contains { !$0.isFiller }, "\(moment)")
            XCTAssertFalse(script.betterWords.contains(where: \.isFiller), "\(moment)")
            XCTAssertFalse(script.firstWords.contains { $0.text.contains("{") || $0.text.contains("}") }, "\(moment)")
            // Ids stay unique across both takes, so the flow layout never
            // confuses a word leaving with one arriving.
            let ids = (script.firstWords + script.betterWords).map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(moment)")
        }
    }

    func testDemoParsesBracedFillers() {
        let words = DemoScript.words("{Um, so,} I grew up {like,} here.", idBase: 0)
        XCTAssertEqual(words.map(\.text), ["Um,", "so,", "I", "grew", "up", "like,", "here."])
        XCTAssertEqual(words.map(\.isFiller), [true, true, false, false, false, true, false])
    }

    func testPromiseNamesTheirMomentAndOutcomes() {
        XCTAssertEqual(SpeakingMoment.interview.promise(outcomes: [.calm, .clear]), "and you'll walk into your interview calm and clear.")
        XCTAssertEqual(SpeakingMoment.everyday.promise(outcomes: [.fluent]), "and you'll speak fluently, every day.")
        XCTAssertEqual(SpeakingMoment.ielts.promise(outcomes: []), "and you'll walk into your speaking test ready.")
    }

    func testOutcomeOptionsFitTheMoment() {
        XCTAssertFalse(SpeakingMoment.ielts.outcomeOptions.contains(.getTheYes))
        XCTAssertTrue(SpeakingMoment.ielts.outcomeOptions.contains(.fluent))
        XCTAssertTrue(SpeakingMoment.raise.outcomeOptions.contains(.getTheYes))
    }

    func testNoPainMeansNoCostQuestion() {
        var answers = OnboardingAnswers()
        answers.statements = Dictionary(uniqueKeysWithValues: PainStatement.allCases.map { ($0, Agreement.no) })
        XCTAssertFalse(answers.reportsPain)
        answers.statements[.stayQuiet] = .sometimes
        XCTAssertTrue(answers.reportsPain)
    }

    func testLanguageShortListLeadsWithTheSelectionAvailable() {
        XCTAssertTrue(PracticeLanguage.shortList(selected: "ja").contains { $0.id == "ja" })
        let list = PracticeLanguage.shortList(selected: "en").map(\.id)
        XCTAssertEqual(Set(list).count, list.count)
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
        XCTAssertNotNil(moment.firstPractice)
        XCTAssertFalse(moment.readinessQuestion.contains("everyday conversations right now"))
        XCTAssertFalse(moment.promise(outcomes: [.calm]).contains("walk into"))
        XCTAssertFalse(SpeakingMoment.interview.isGeneral)
    }
}
