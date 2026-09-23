import XCTest
@testable import SpeakingCoach

final class RoutineTests: XCTestCase {
    private var calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    /// 2030-05-06 is a Monday (weekday 2).
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 6) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 5, day: day, hour: hour, minute: minute))!
    }

    func testDaytimeWindow() {
        let weekdays = [2, 3, 4, 5, 6]
        XCTAssertTrue(RoutineShared.isInWindow(start: 9 * 60, end: 17 * 60, days: weekdays, at: at(9), calendar: calendar))
        XCTAssertFalse(RoutineShared.isInWindow(start: 9 * 60, end: 17 * 60, days: weekdays, at: at(17), calendar: calendar))
        XCTAssertFalse(RoutineShared.isInWindow(start: 9 * 60, end: 17 * 60, days: weekdays, at: at(10, day: 5), calendar: calendar), "Sunday is off")
    }

    func testOvernightWindowBelongsToTheDayItStarted() {
        // Sunday night only: 22:00 → 07:00.
        let sunday = [1]
        XCTAssertTrue(RoutineShared.isInWindow(start: 22 * 60, end: 7 * 60, days: sunday, at: at(23, day: 5), calendar: calendar))
        XCTAssertTrue(RoutineShared.isInWindow(start: 22 * 60, end: 7 * 60, days: sunday, at: at(6), calendar: calendar), "Monday early morning is Sunday's night")
        XCTAssertFalse(RoutineShared.isInWindow(start: 22 * 60, end: 7 * 60, days: sunday, at: at(23), calendar: calendar), "Monday night is off")
    }

    func testEqualTimesMeanAllDay() {
        XCTAssertTrue(RoutineShared.isInWindow(start: 600, end: 600, days: [2], at: at(3), calendar: calendar))
    }

    func testSayItNeedsTheWordsInOrder() {
        let prompt = DailyPrompt.all.first { $0.id == "say-pause" }!
        XCTAssertTrue(prompt.evaluate("When I slow down, people listen more closely.").passed)
        XCTAssertTrue(prompt.evaluate("um when I slow down people listen closely").passed, "Fillers and a dropped word are fine")
        XCTAssertFalse(prompt.evaluate("closely more listen people down slow").passed)
    }

    func testAnswersNeedARealSentence() {
        let prompt = DailyPrompt.all.first { $0.id == "answer-weekend" }!
        XCTAssertFalse(prompt.evaluate("a walk").passed)
        XCTAssertTrue(prompt.evaluate("A long walk with my sister because we never get time together").passed)
    }

    func testDescriptionsNeedTheScene() {
        let prompt = DailyPrompt.all.first { $0.id == "describe-cafe" }!
        XCTAssertTrue(prompt.evaluate("Someone is reading a book by the window while it's raining").passed)
        XCTAssertFalse(prompt.evaluate("I like it very much today honestly").passed)
    }

    func testOtherLanguagesOnlyGetOpenQuestions() {
        for offset in 0..<14 {
            let day = Date(timeIntervalSince1970: 1_900_000_000 + Double(offset) * 86_400)
            XCTAssertEqual(DailyPrompt.today(day, language: "es").kind, .answer)
        }
    }
}
