import XCTest

final class AIConsentUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-review-screen=consent", "-review-consent-reset", "-language=en"]
        app.launch()
        return app
    }

    func testDisclosureAndDecline() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Practice with AI"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "ElevenLabs")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "OpenAI")).firstMatch.exists)
        XCTAssertTrue(app.links["Privacy Policy"].exists || app.buttons["Privacy Policy"].exists)
        XCTAssertTrue(app.links["How AI uses your data"].exists || app.buttons["How AI uses your data"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "AI data sharing disclosure"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.staticTexts["AI sharing declined"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["AI sharing allowed"].exists)
    }

    func testExplicitAllowUnlocksGate() {
        let app = launch()
        XCTAssertTrue(app.buttons["Allow and continue"].waitForExistence(timeout: 10))
        app.buttons["Allow and continue"].tap()
        XCTAssertTrue(app.staticTexts["AI sharing allowed"].waitForExistence(timeout: 5))
    }
}
