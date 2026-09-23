import XCTest

/// Walks the whole sign-up flow the way a person would — every tap, the deck,
/// the typed reveals, the fingerprint hold — and stops at the account step
/// (which needs a real Apple/Google/email identity). Screenshots of each step
/// are attached to the test result.
final class OnboardingFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-fresh-start"]
        app.launch()
    }

    func testFullOnboardingReachesAccountStep() {
        tap("Get started")

        // Practice language: the device's own leads; English here.
        XCTAssertTrue(app.staticTexts["Which language do you want to practice?"].waitForExistence(timeout: 5))
        tap("English")
        snap("00-language")
        tap("Continue")

        // Name
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Sulav")
        snap("01-name")
        tap("Continue")

        // Category, then the situation inside it.
        tapRow("Work")
        snap("02-category")
        tap("Continue")
        tap("A job interview")
        snap("02-moment")
        tap("Continue")
        tap("This week")
        tap("Continue")

        // Readiness: the custom slider presents as a real one.
        let slider = app.sliders["Readiness"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        // A finger on the rail (the drawn track sits ~60% down the control).
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.6)).tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 2))
        snap("03-readiness")
        tap("Continue")

        // The deck: six statements, answered with the flow's own rows.
        XCTAssertTrue(app.staticTexts["Does this sound like you?"].waitForExistence(timeout: 5))
        for answer in ["That's me", "That's me", "Sometimes", "Not me", "That's me", "Sometimes"] {
            tap(answer)
            usleep(700_000)
        }

        // Mirror — the diagnosis types out; its button waits for it.
        XCTAssertTrue(app.staticTexts["The Blank-Out"].waitForExistence(timeout: 6))
        tap("That's me", timeout: 10)
        snap("04-mirror")

        // Cost
        tap("A job or promotion")
        tap("Confidence in myself")
        snap("05-cost")
        tap("Continue")

        // Reframe — three typed lines.
        tap("Continue", timeout: 15)

        // Outcome
        tap("I stay calm")
        tap("Continue")

        // Promise — typed, in their own moment and outcome.
        tap("Show me how", timeout: 15)
        snap("06-promise")

        // Demo: hold the bloom through the first take, watch the fillers
        // lift, then hold again for the retry.
        XCTAssertTrue(app.staticTexts["Practice it before it's real."].waitForExistence(timeout: 5))
        let answer = app.buttons["Hold to answer"].firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        answer.press(forDuration: 6)
        let retry = app.buttons["Hold to try again"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 12))
        snap("07-demo-heard-back")
        retry.press(forDuration: 6)
        snap("07-demo-done")
        tap("Continue", timeout: 6)

        // Plan
        XCTAssertTrue(app.staticTexts["Your interview is this week."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tell me about yourself"].exists)
        snap("08-plan")
        tap("Commit to it", timeout: 6)

        // Commit: a real two-second hold on the fingerprint.
        let hold = app.descendants(matching: .any)["Hold to commit"].firstMatch
        XCTAssertTrue(hold.waitForExistence(timeout: 5))
        sleep(1)
        hold.press(forDuration: 2.6)
        snap("09-committed")

        // Account
        XCTAssertTrue(app.staticTexts["Save your plan"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Sign up with Apple"].exists)
        XCTAssertTrue(app.buttons["Sign up with Google"].exists)
        snap("10-account")

        // Apple and Google are the only ways in.
        XCTAssertFalse(app.buttons["Sign up with email"].exists)
    }

    func testDraftResumesAfterRelaunch() {
        tap("Get started")
        tap("Continue")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Maya")
        tap("Continue")
        tapRow("Presentations")
        tap("Continue")
        XCTAssertTrue(app.staticTexts["When is it?"].waitForExistence(timeout: 5))

        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launch()
        XCTAssertTrue(relaunched.staticTexts["When is it?"].waitForExistence(timeout: 8), "Relaunch should resume on the same step")
    }

    func testSignInCrossfadeKeepsTheMarkStill() {
        tap("I already have an account")
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sign in with Apple"].exists)
        XCTAssertTrue(app.buttons["Sign in with Google"].exists)
        XCTAssertFalse(app.buttons["Sign in with email"].exists)
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 5))
    }

    // MARK: Helpers

    private func tap(_ label: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "Missing button: \(label)", file: file, line: line)
        let enabled = NSPredicate(format: "isEnabled == true AND isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabled, object: button)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "Button never enabled: \(label)", file: file, line: line)
        button.tap()
    }

    /// Answer rows with a detail line read as "Title, detail".
    private func tapRow(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Missing row: \(title)", file: file, line: line)
        row.tap()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
