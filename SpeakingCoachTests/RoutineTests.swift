import XCTest
@testable import SpeakingCoach

final class RoutineTests: XCTestCase {
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

    func testOtherLanguagesNeverGetEnglishPictureChecks() {
        AppLanguage.choose("es")
        defer { AppLanguage.choose("en") }
        for offset in 0..<14 {
            let day = Date(timeIntervalSince1970: 1_900_000_000 + Double(offset) * 86_400)
            XCTAssertNotEqual(DailyPrompt.today(day).kind, .describe)
        }
    }
}
