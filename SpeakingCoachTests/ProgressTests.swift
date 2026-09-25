import XCTest
@testable import SpeakingCoach

final class ProgressTests: XCTestCase {
    private let evidence = PracticeCatalog.definition("interview_evidence")!
    private let update = PracticeCatalog.definition("clear_work_update")!

    private func record(
        _ practice: PracticeDefinition?, _ levels: [Int] = [], at date: Date = .now,
        parent: UUID? = nil, criterion: Int? = nil
    ) -> PracticeRecord {
        let criteria: [CriterionLevel] = practice.map { practice in
            if let criterion { return [CriterionLevel(id: practice.criteria[criterion].id, level: levels[0])] }
            return zip(practice.criteria, levels).map { CriterionLevel(id: $0.id, level: $1) }
        } ?? []
        return PracticeRecord(
            id: UUID(), activityID: practice?.id, title: practice?.title ?? "Custom", date: date,
            score: nil, parentID: parent, criteria: criteria, isCustom: practice == nil
        )
    }

    // MARK: Rehearsals

    func testRetriesSitUnderTheirRehearsalWhichRisesToTheirDate() {
        let rehearsal = record(evidence, [2, 1, 0], at: .now.addingTimeInterval(-86_400 * 3))
        let other = record(update, [2, 2, 2], at: .now.addingTimeInterval(-86_400))
        let retry = record(evidence, [2], at: .now, parent: rehearsal.id, criterion: 1)

        let entries = RehearsalEntry.entries(from: [retry, other, rehearsal])

        XCTAssertEqual(entries.map(\.record.id), [rehearsal.id, other.id])
        XCTAssertEqual(entries.first?.retries.map(\.id), [retry.id])
    }

    func testARetryWhoseRehearsalIsntLoadedStandsAlone() {
        let retry = record(evidence, [2], parent: UUID(), criterion: 1)
        let entries = RehearsalEntry.entries(from: [retry])
        XCTAssertEqual(entries.map(\.record.id), [retry.id])
        XCTAssertEqual(entries.first?.retries, [])
    }

    // MARK: Calendar

    func testCalendarEndsOnThisWeekAndCountsItsRehearsals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 2 // Monday
        // Thursday 24 September 2026, midday.
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12)))
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: now)! }

        let weeks = PracticeWeeks(
            records: [record(evidence, [2, 2, 2], at: now), record(update, [1, 1, 1], at: day(-1)), record(evidence, [0, 0, 0], at: day(-8))],
            now: now, calendar: calendar
        )

        XCTAssertEqual(weeks.rows.count, 5)
        XCTAssertEqual(weeks.rows.last?.first?.number, 21) // Monday 21st
        XCTAssertEqual(weeks.rows.first?.first?.number, 24) // Monday 24 August
        XCTAssertEqual(weeks.thisWeek, 2)
        XCTAssertEqual(weeks.daysPracticed, 3)
        XCTAssertEqual(weeks.rows.last?.filter(\.isToday).map(\.number), [24])
        XCTAssertEqual(weeks.rows.last?.filter(\.isFuture).count, 3) // Friday to Sunday
    }

    func testRelativeDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12)))
        XCTAssertTrue(SessionText.when(now, now: now, calendar: calendar).hasPrefix("Today, "))
        XCTAssertTrue(SessionText.when(now.addingTimeInterval(-86_400), now: now, calendar: calendar).hasPrefix("Yesterday, "))
        XCTAssertEqual(SessionText.day(now, now: now, calendar: calendar), "today")
        XCTAssertEqual(SessionText.day(now.addingTimeInterval(-86_400), now: now, calendar: calendar), "yesterday")
    }
}
