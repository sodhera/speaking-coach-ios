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

    // MARK: Remote copy

    func testEmptyMetadataKeepsTheShippedCopy() {
        XCTAssertEqual(PaywallCopy(metadata: [:]), PaywallCopy())
    }

    func testMetadataOverridesEachField() {
        let copy = PaywallCopy(metadata: [
            "headline": "  Your voice, ready.  ",
            "benefits": [["lead": "Rehearse it", "detail": "{practice}"]],
            "plans_title": "Pick a plan",
            "reassurance": "Cancel in two taps.",
            "cta_trial": "Try {trial} free",
            "cta": "Get {plan}",
            "default_plan": "monthly",
            "show_badge": false,
        ])
        XCTAssertEqual(copy.headline, "Your voice, ready.")
        XCTAssertEqual(copy.benefits, [.init(lead: "Rehearse it", detail: "{practice}")])
        XCTAssertEqual(copy.plansTitle, "Pick a plan")
        XCTAssertEqual(copy.reassurance, "Cancel in two taps.")
        XCTAssertEqual(copy.trialCallToAction, "Try {trial} free")
        XCTAssertEqual(copy.callToAction, "Get {plan}")
        XCTAssertFalse(copy.preselectsAnnual)
        XCTAssertFalse(copy.showsBadge)
    }

    func testMalformedMetadataFallsBack() {
        let copy = PaywallCopy(metadata: [
            "headline": "",
            "plans_title": 42,
            "benefits": [["lead": "Only a lead"]],
            "default_plan": "weekly",
            "show_badge": "no",
        ])
        XCTAssertEqual(copy, PaywallCopy())
    }

    func testUnknownTokensNeverReachTheScreen() {
        let defaults = PaywallCopy()
        let copy = PaywallCopy(metadata: [
            "headline": "Hi {name}",
            "cta": "Start {practice}",
            "benefits": [["lead": "Fine", "detail": "{practise}"], ["lead": "Also fine", "detail": "Words."]],
        ])
        XCTAssertEqual(copy.headline, defaults.headline)
        XCTAssertEqual(copy.callToAction, defaults.callToAction)
        XCTAssertEqual(copy.benefits, defaults.benefits)
    }

    func testBenefitsAreOneToFour() {
        let five = Array(repeating: ["lead": "A", "detail": "B"], count: 5)
        XCTAssertEqual(PaywallCopy(metadata: ["benefits": five]).benefits, PaywallCopy().benefits)
        XCTAssertEqual(PaywallCopy(metadata: ["benefits": [[String: String]]()]).benefits, PaywallCopy().benefits)
    }

    func testTokensFillWithTheUsersAnswers() {
        XCTAssertEqual(PaywallCopy.fill("{headline} {retry}", ["headline": "Walk in calm.", "retry": "Again."]), "Walk in calm. Again.")
        XCTAssertEqual(PaywallCopy.fill("Start {trial} Free Trial", ["trial": "1-Week"]), "Start 1-Week Free Trial")
        XCTAssertEqual(PaywallCopy.tokens(in: "{a} and {b_c}"), ["a", "b_c"])
    }

    func testDefaultBenefitsStillPersonalize() {
        XCTAssertEqual(PaywallView.practiceLine(for: .presentation), "Your opening, out loud, until it lands.")
        XCTAssertEqual(PaywallCopy().benefits.first?.detail, "{practice}")
    }
}
