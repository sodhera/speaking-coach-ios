import XCTest
@testable import SpeakingCoach

final class FirstPlanTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLanguage.choose("en")
    }

    private func profile(_ moment: SpeakingMoment? = .raise, legacy: Bool = false) -> CoachProfile {
        CoachProfile(
            name: "Sam", language: "en", moment: moment, timing: .thisWeek, readiness: 5,
            statements: [:], costs: [], outcomes: [.clear], onboardedAt: .now, isLegacy: legacy
        )
    }

    private func record(_ activity: String?, parent: UUID? = nil) -> PracticeRecord {
        PracticeRecord(id: UUID(), activityID: activity, title: "", date: .now, score: nil, parentID: parent)
    }

    func testNewUserStartsOnRehearse() {
        let plan = FirstPlan(profile: profile(), records: [])
        XCTAssertEqual(plan?.current, .rehearse)
        XCTAssertEqual(plan?.finish, "Walk in clear")
    }

    func testOtherRehearsalsDontTickTheFirstStep() {
        let plan = FirstPlan(profile: profile(), records: [record("interview_tell_me_about_yourself")])
        XCTAssertEqual(plan?.current, .rehearse)
    }

    func testPlanRehearsalMovesToRetryAndPointsAtIt() {
        let first = record("salary_raise")
        let plan = FirstPlan(profile: profile(), records: [first])
        XCTAssertEqual(plan?.current, .retry)
        XCTAssertEqual(plan?.retryFrom?.id, first.id)
    }

    func testARetryStartedButLeftIsntOfferedAgainNorCountedDone() {
        // The server counts a retry as used once it starts, feedback or not.
        let older = record("salary_raise")
        let newer = record("salary_raise")
        let plan = FirstPlan(profile: profile(), records: [newer, older], startedRetries: [newer.id])
        XCTAssertEqual(plan?.current, .retry, "No feedback came back, so step two isn't done")
        XCTAssertEqual(plan?.retryFrom?.id, older.id, "Step two goes to a session whose retry is still free")

        let spent = FirstPlan(profile: profile(), records: [newer], startedRetries: [newer.id])
        XCTAssertNil(spent?.retryFrom, "With no free retry, step two runs the whole scene again")
    }

    func testRetryOfThePlanRehearsalMovesToFinish() {
        let first = record("salary_raise")
        let plan = FirstPlan(profile: profile(), records: [record("salary_raise", parent: first.id), first])
        XCTAssertEqual(plan?.current, .finish)
        XCTAssertTrue(plan?.isDone(.retry) ?? false)
    }

    func testCheckInCompletesThePlan() {
        var done = profile()
        done.planReadiness = 7
        done.planCompletedAt = .now
        XCTAssertEqual(FirstPlan(profile: done, records: [])?.isComplete, true)
    }

    func testNoPlanForOldAppAccountsOrMissingMoment() {
        XCTAssertNil(FirstPlan(profile: profile(legacy: true), records: []))
        XCTAssertNil(FirstPlan(profile: profile(nil), records: []))
        XCTAssertNil(FirstPlan(profile: nil, records: []))
    }

    func testGeneralFinishNeverPromisesWalkingIn() {
        XCTAssertEqual(SpeakingMoment.everyday.planFinish(outcomes: [.calm]), "Speak calmly, every day")
    }
}
