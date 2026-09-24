import XCTest

final class ZaraRecordingUITests: XCTestCase {
    func testZaraWalkthrough() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-zara-demo", "-review-access=entitled"]
        app.launch()

        let start = app.buttons["Get started"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        sleep(75)
        start.tap()

        let continueAsZara = app.buttons["Continue as Zara"]
        XCTAssertTrue(continueAsZara.waitForExistence(timeout: 10))
        sleep(2)
        continueAsZara.tap()

        let slides = app.buttons["Practise with my slides"]
        XCTAssertTrue(slides.waitForExistence(timeout: 15))
        sleep(2)
        app.swipeUp()
        sleep(2)
        app.swipeDown()
        sleep(2)
        slides.tap()
        let deck = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "When Nerves Show Up")).firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        sleep(2)
        deck.tap()
        XCTAssertTrue(app.staticTexts["Your audience"].waitForExistence(timeout: 10))
        sleep(2)

        let audience = app.textFields["e.g. the leadership team"]
        typeSlowly("my psychology class", into: audience)
        let purpose = app.textFields["e.g. approve the budget for Q3"]
        typeSlowly("help classmates speak even when nervous", into: purpose)
        let instructions = app.textFields.element(boundBy: 3)
        typeSlowly("I rush when I feel watched. Please ask gentle questions and let me pause.", into: instructions)

        app.swipeDown()
        sleep(2)
        let gently = app.buttons["Gently"]
        XCTAssertTrue(gently.waitForExistence(timeout: 10))
        gently.tap()
        sleep(2)

        let practise = app.buttons["Practise it"]
        XCTAssertTrue(practise.waitForExistence(timeout: 10))
        practise.tap()
        XCTAssertTrue(app.buttons["Next slide"].waitForExistence(timeout: 10))
        sleep(3)
        for _ in 0..<4 {
            app.buttons["Next slide"].tap()
            sleep(1)
        }
        app.buttons["Previous slide"].tap()
        sleep(2)
        app.buttons["Finish and get questions"].tap()
        sleep(1)
        app.sheets["Finish this presentation?"].buttons["Finish and get questions"].tap()
        let audienceQuestions = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "your audience asks")).firstMatch
        XCTAssertTrue(audienceQuestions.waitForExistence(timeout: 10))
        sleep(3)
        for _ in 0..<5 {
            app.swipeUp()
            sleep(2)
        }
        let transcript = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "what you said")).firstMatch
        if transcript.exists { transcript.tap() }
        sleep(3)
        app.swipeDown()
        sleep(2)
        print("ZARA_RESULTS_TREE: \(app.debugDescription)")
        sleep(60)
    }

    private func typeSlowly(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        for character in text {
            field.typeText(String(character))
            usleep(80_000)
        }
        sleep(1)
    }
}
