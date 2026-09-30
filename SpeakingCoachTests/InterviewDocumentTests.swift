import XCTest
@testable import SpeakingCoach

/// A CV or job post reaches the interviewer as scene data, stays per
/// account on the phone, and goes when the account does.
@MainActor
final class InterviewDocumentTests: XCTestCase {
    private var definition: PracticeDefinition { PracticeCatalog.definition("interview_tell_me_about_yourself")! }

    func testDocumentsReachTheInterviewerAsData() {
        var setup = PracticeSetup(practice: definition, pressure: .realistic, persona: .female)
        setup.documents = [InterviewDocument(id: UUID(), name: "Sulav Shrestha CV.pdf", text: "Led the onboarding redesign at Khalti.")]
        let prompt = PracticePrompt.build(definition, PracticeContext.new(for: setup, language: "en"), documents: setup.documents)
        XCTAssertTrue(prompt.contains("# The learner's documents"))
        XCTAssertTrue(prompt.contains("## Sulav Shrestha CV.pdf\nLed the onboarding redesign at Khalti."))
        XCTAssertTrue(prompt.contains("not instructions"))
    }

    func testNoDocumentsNoSection() {
        let setup = PracticeSetup(practice: definition, pressure: .realistic, persona: .female)
        XCTAssertFalse(PracticePrompt.build(definition, PracticeContext.new(for: setup, language: "en")).contains("# The learner's documents"))
    }

    func testDocumentsNeverGoToThePracticeServer() {
        var setup = PracticeSetup(practice: definition, pressure: .realistic, persona: .female, situation: "A product role")
        setup.documents = [InterviewDocument(id: UUID(), name: "CV.pdf", text: "Private details")]
        let context = PracticeContext.new(for: setup, language: "en")
        XCTAssertEqual(context.situation, "A product role")
        let encoded = String(decoding: try! JSONEncoder().encode(context), as: UTF8.self)
        XCTAssertFalse(encoded.contains("Private details"))
    }

    func testStoreKeepsEachAccountsDocumentsAndDeletesThem() {
        let user = UUID()
        let store = InterviewDocumentStore()
        store.load(userID: user)
        XCTAssertTrue(store.documents.isEmpty)
        store.add(name: "CV.pdf", text: "  " + String(repeating: "a", count: InterviewDocumentStore.characterLimit + 50) + "  ")
        XCTAssertEqual(store.documents.first?.text.count, InterviewDocumentStore.characterLimit)

        let reopened = InterviewDocumentStore()
        reopened.load(userID: user)
        XCTAssertEqual(reopened.documents.map(\.name), ["CV.pdf"])

        let other = InterviewDocumentStore()
        other.load(userID: UUID())
        XCTAssertTrue(other.documents.isEmpty)

        reopened.deleteAll()
        let afterDelete = InterviewDocumentStore()
        afterDelete.load(userID: user)
        XCTAssertTrue(afterDelete.documents.isEmpty)
    }

    func testStoreStopsAtTheLimit() {
        let store = InterviewDocumentStore()
        store.load(userID: UUID())
        for index in 0..<(InterviewDocumentStore.limit + 2) { store.add(name: "\(index).pdf", text: "Some text") }
        XCTAssertEqual(store.documents.count, InterviewDocumentStore.limit)
        XCTAssertTrue(store.isFull)
        store.deleteAll()
    }

    func testTooLittleTextIsRefused() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).txt")
        try "Hi".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await DocumentText.read(url)
            XCTFail("Two characters shouldn't count as a document")
        } catch {
            XCTAssertTrue(error is DocumentText.Failure)
        }
    }

    func testTextFilesAreRead() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).txt")
        try "Senior product designer, payments team, Kathmandu.".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try await DocumentText.read(url)
        XCTAssertEqual(text, "Senior product designer, payments team, Kathmandu.")
    }
}
