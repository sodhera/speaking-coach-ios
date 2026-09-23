import XCTest
@testable import SpeakingCoach

final class PreparationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func plan(program: String = "interview", event: Date? = nil) -> PreparationPlan {
        PreparationPlan(programID: program, eventName: "", eventDate: event, reminderEnabled: true, createdAt: start, reflection: nil)
    }

    private func record(_ id: String, at date: Date, retryOf parent: UUID? = nil) -> PracticeRecord {
        PracticeRecord(id: UUID(), activityID: id, title: id, date: date, score: nil, parentID: parent)
    }

    func testEveryProgramPracticeIsInTheCatalog() {
        for program in PreparationProgram.all {
            XCTAssertEqual(program.practices.count, program.practiceIDs.count, program.id)
        }
    }

    func testOnlyFirstRehearsalsSinceThePlanBeganCount() {
        let later = start.addingTimeInterval(3600)
        let records = [
            record("interview_tell_me_about_yourself", at: start.addingTimeInterval(-3600)), // before the plan
            record("interview_evidence", at: later),
            record("interview_pressure", at: later, retryOf: UUID()),                       // a retry
            record("salary_raise", at: later),                                              // not in this plan
        ]
        XCTAssertEqual(plan().completedIDs(in: records), ["interview_evidence"])
        XCTAssertEqual(plan().next(in: records)?.id, "interview_tell_me_about_yourself")
    }

    func testReminderIsTheMorningBeforeOrTheMorningOf() {
        let calendar = Calendar.current
        let event = calendar.date(from: DateComponents(year: 2030, month: 5, day: 10, hour: 0))!
        let dayBefore = calendar.date(from: DateComponents(year: 2030, month: 5, day: 9, hour: 9))!
        let morningOf = calendar.date(from: DateComponents(year: 2030, month: 5, day: 10, hour: 9))!

        XCTAssertEqual(PreparationPlan.reminderDate(for: event, now: dayBefore.addingTimeInterval(-60)), dayBefore)
        XCTAssertEqual(PreparationPlan.reminderDate(for: event, now: dayBefore.addingTimeInterval(60)), morningOf)
        XCTAssertNil(PreparationPlan.reminderDate(for: event, now: morningOf.addingTimeInterval(60)))
    }

    func testDaysUntilTheEvent() {
        let now = Date()
        let inFive = Calendar.current.date(byAdding: .day, value: 5, to: now)!
        XCTAssertEqual(plan(event: inFive).daysUntilEvent(from: now), 5)
        XCTAssertEqual(plan(event: now).daysUntilEvent(from: now), 0)
        XCTAssertNil(plan().daysUntilEvent(from: now))
    }

    func testThePlanRoundTripsThroughTheAccount() throws {
        var original = plan(event: start)
        original.reflection = .init(outcome: .notYet, note: "Nerves", recordedAt: start)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let json = try String(data: encoder.encode(original), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"not_used\""), "Outcome keeps the old app's raw value")
        XCTAssertEqual(try decoder.decode(PreparationPlan.self, from: Data(json.utf8)), original)
    }
}
