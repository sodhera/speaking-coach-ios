import XCTest
@testable import SpeakingCoach

@MainActor
final class PaywallLogicTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLanguage.choose("en")
    }

    private func profile(_ moment: SpeakingMoment?, _ outcomes: [SpeakingOutcome]) -> CoachProfile {
        CoachProfile(name: "Sulav", language: "en", moment: moment, timing: .thisWeek, readiness: 4,
                     statements: [:], costs: [], outcomes: outcomes, onboardedAt: .now)
    }

    func testHeadlineSellsBackTheUsersOwnOutcome() {
        XCTAssertEqual(PaywallView.headline(for: profile(.interview, [.calm, .clear])), "Walk into your interview calm and clear.")
        XCTAssertEqual(PaywallView.headline(for: profile(.raise, [.getTheYes])), "Walk into the raise conversation ready to get the yes.")
        XCTAssertEqual(PaywallView.headline(for: profile(.meetingPeople, [.myself])), "Walk into any room sounding like yourself.")
    }

    func testHeadlineUsesAtMostTwoOutcomes() {
        let headline = PaywallView.headline(for: profile(.presentation, [.calm, .clear, .myself]))
        XCTAssertEqual(headline, "Walk into your presentation calm and clear.")
    }

    func testLegacyAccountsGetTheBrandLine() {
        XCTAssertEqual(PaywallView.headline(for: nil), "Practice the conversations that matter.")
        XCTAssertEqual(PaywallView.headline(for: profile(nil, [])), "Practice the conversations that matter.")
    }

    func testUsersOwnMomentCategoryLeadsTheCatalog() {
        XCTAssertEqual(PracticeCategory.ordered(firstFor: .presentation).first, .big_moments)
        XCTAssertEqual(PracticeCategory.ordered(firstFor: .raise).first, .work)
        XCTAssertEqual(PracticeCategory.ordered(firstFor: nil), PracticeCategory.allCases)
        XCTAssertEqual(Set(PracticeCategory.ordered(firstFor: .interview)), Set(PracticeCategory.allCases))
    }

    func testEveryCatalogPracticeHasAKnownCategory() {
        let known = Set(PracticeCategory.allCases.map(\.rawValue))
        for practice in PracticeCatalog.all {
            XCTAssertTrue(known.contains(practice.category), "\(practice.id) has category \(practice.category)")
        }
    }

    func testTrialsReadTheWayPeopleSayThem() {
        func plan(_ days: Int) -> Plan {
            Plan(id: "a", isAnnual: true, name: "Yearly", priceString: "$1", trialDays: days, priceValue: 1)
        }
        XCTAssertEqual(plan(7).trialPhrase, "1 week")
        XCTAssertEqual(plan(14).trialPhrase, "2 weeks")
        XCTAssertEqual(plan(3).trialPhrase, "3 days")
        XCTAssertEqual(plan(30).trialPhrase, "1 month")
        XCTAssertNil(plan(0).trialPhrase)
        AppLanguage.choose("de")
        XCTAssertEqual(plan(7).trialPhrase, "1 Woche")
    }

    func testGeneralImprovementNeverPromisesAnEvent() {
        XCTAssertEqual(PaywallView.headline(for: profile(.everyday, [.calm, .clear])), "Speak calmly and clearly, every day.")
        XCTAssertEqual(PaywallView.headline(for: profile(.everyday, [.myself])), "Speak like yourself, every day.")
        XCTAssertFalse(PaywallView.headline(for: profile(.everyday, [.getTheYes])).contains("Walk into"))
    }
}
