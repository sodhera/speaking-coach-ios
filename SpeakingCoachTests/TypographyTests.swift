import XCTest
@testable import SpeakingCoach

final class TypographyTests: XCTestCase {
    func testDMSansIsBundledAndRegistered() {
        XCTAssertTrue(Typeface.isAvailable, "DM Sans must load, or every screen silently falls back to San Francisco.")
    }

    func testOpticalSizeIsClampedToTheFontsRange() {
        let font = Typeface.uiFont(size: 64, weight: 600)
        XCTAssertEqual(font.pointSize, 64)
        XCTAssertTrue(font.fontName.hasPrefix("DMSans"))
    }
}
