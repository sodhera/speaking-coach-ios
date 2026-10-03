import XCTest
@testable import SpeakingCoach

@MainActor
final class AIConsentTests: XCTestCase {
    private var previousUserID: UUID?
    private var account: UUID!

    override func setUp() async throws {
        previousUserID = AIConsent.userID
        account = UUID()
        AIConsent.identify(account)
        AIConsent.revoke()
    }

    override func tearDown() async throws {
        AIConsent.identify(account)
        AIConsent.revoke()
        AIConsent.identify(previousUserID)
    }

    func testConsentCannotCarryBetweenAccountsOrSignedOutState() throws {
        AIConsent.give()
        try AIConsent.require(userID: account)
        let other = UUID()
        XCTAssertThrowsError(try AIConsent.require(userID: other))
        AIConsent.identify(other)
        XCTAssertFalse(AIConsent.isGiven)
        AIConsent.identify(nil)
        AIConsent.give()
        XCTAssertFalse(AIConsent.isGiven)
        AIConsent.identify(account)
        XCTAssertTrue(AIConsent.isGiven)
    }

    func testOldDisclosureDoesNotAuthorizeBroaderSharing() {
        let oldKey = "sc.aiConsent.v1"
        let previous = UserDefaults.standard.object(forKey: oldKey)
        defer { UserDefaults.standard.set(previous, forKey: oldKey) }
        UserDefaults.standard.set(true, forKey: oldKey)
        XCTAssertFalse(AIConsent.isGiven)
        XCTAssertThrowsError(try AIConsent.require())
    }

    func testGateHoldsTheActionAndRevocationBlocksItAgain() {
        var calls = 0
        let held = AIConsent.gate { calls += 1 }
        XCTAssertNotNil(held)
        XCTAssertEqual(calls, 0)
        AIConsent.give()
        XCTAssertNil(AIConsent.gate { calls += 1 })
        XCTAssertEqual(calls, 1)
        AIConsent.revoke()
        XCTAssertNotNil(AIConsent.gate { calls += 1 })
        XCTAssertEqual(calls, 1)
    }

    private func assertConsentBlocked<T>(_ action: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await action()
            XCTFail("Request was allowed without consent", file: file, line: line)
        } catch PracticeAPIError.aiConsentRequired {
            // The transport must stop before authentication, file reads or networking.
        } catch {
            XCTFail("Expected consent refusal, got \(error)", file: file, line: line)
        }
    }

    func testAITransportsRejectWithoutConsentBeforeReadingOrSendingData() async {
        // Previously accepted permission must also stop authorizing all routes.
        AIConsent.give()
        AIConsent.revoke()
        let context = PracticeContext(attemptId: UUID(), activityId: "private", activityVersion: 1, rubricVersion: "v1", language: "en", pressure: "realistic", pacing: "patient", situation: "Private notes", startedAt: "")
        let deck = PresentationDeck(id: UUID(), title: "Private slides", createdAt: .now, updatedAt: .now, fileName: "private.pdf", slideCount: 1, slideTexts: ["Private text"])
        let question = AudienceQuestion(id: "q", question: "Why?", reason: "Context", slideIndex: 0)
        let situation = CustomSituation(description: "Personal situation", partner: "My manager", title: "Work")
        await assertConsentBlocked { try await PracticeAPI.start(context) }
        await assertConsentBlocked { try await CustomSituationAPI.analyze([], situation: situation, language: "en") }
        await assertConsentBlocked { try await PresentationAPI.questions(deck: deck, transcript: "Private words", events: []) }
        await assertConsentBlocked { try await PresentationAPI.feedback(deck: deck, question: question, answer: "Private answer", talk: "Private talk") }
        await assertConsentBlocked { try await PracticeAPI.assess(attemptId: UUID(), transcript: []) }
        await assertConsentBlocked { try await CustomSituationAPI.evaluate("Personal situation", language: "en") }
        await assertConsentBlocked { try await CustomSituationAPI.token(persona: .female) }
        await assertConsentBlocked { try await PresentationAPI.transcribe(URL(fileURLWithPath: "/missing-private-recording.m4a"), language: "en") }
        await assertConsentBlocked { try await PresentationAPI.convert(pptx: Data(), fileName: "private.pptx") }
        let voice = VoiceSession()
        await assertConsentBlocked { try await voice.start(token: "invalid", prompt: "Private CV", firstMessage: nil, language: "en", duration: 30) }
        XCTAssertEqual(voice.phase, .idle)
    }
}
