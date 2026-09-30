import Foundation
import Observation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision

/// A CV, a job post or the user's own notes, as the text the interviewer
/// reads. Only the text is kept: the file itself never leaves the picker.
struct InterviewDocument: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let text: String
}

/// The documents an interview is practiced against, one list per account,
/// on this device only (Application Support, complete file protection).
/// Every interview session sends their text to the voice partner as scene
/// data, so the interviewer can ask about the user's real experience and the
/// real role. Dropped from memory on sign-out, deleted with the account.
@MainActor
@Observable
final class InterviewDocumentStore {
    /// Enough for a CV, a job post and notes without crowding the prompt.
    static let limit = 4
    /// Per document; a two-page CV is well under this.
    static let characterLimit = 6000

    private(set) var documents: [InterviewDocument] = []
    private var userID: UUID?

    private static func url(for userID: UUID) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appending(path: "Practice", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "interview-documents-\(userID.uuidString.lowercased()).json")
    }

    func load(userID: UUID) {
        guard userID != self.userID else { return }
        self.userID = userID
        documents = Self.url(for: userID)
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([InterviewDocument].self, from: $0) } ?? []
    }

    /// Signed out: nothing of this account stays in memory.
    func unload() {
        userID = nil
        documents = []
    }

    /// The account is gone, so its documents go too.
    func deleteAll() {
        if let userID, let url = Self.url(for: userID) { try? FileManager.default.removeItem(at: url) }
        documents = []
    }

    var isFull: Bool { documents.count >= Self.limit }

    func add(name: String, text: String) {
        guard !isFull else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        documents.append(InterviewDocument(id: UUID(), name: name, text: String(trimmed.prefix(Self.characterLimit))))
        persist()
    }

    func remove(_ document: InterviewDocument) {
        documents.removeAll { $0.id == document.id }
        persist()
    }

    private func persist() {
        guard let userID, let url = Self.url(for: userID), let data = try? JSONEncoder().encode(documents) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    #if DEBUG
    func setReviewDocuments(_ documents: [InterviewDocument]) {
        self.documents = documents
    }
    #endif
}

/// Reads a document's words on the phone: a PDF's text layer, a text or RTF
/// file, or a photo of a page through on-device text recognition.
enum DocumentText {
    enum Failure: LocalizedError {
        case noText
        var errorDescription: String? {
            String(localized: "We couldn't find any text in that. Try a PDF, or a clear photo of the page.", bundle: AppLanguage.bundle)
        }
    }

    static let fileTypes: [UTType] = [.pdf, .plainText, .rtf, .image]

    static func read(_ url: URL) async throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        let text: String
        if type.conforms(to: .pdf) {
            text = PDFDocument(url: url)?.string ?? ""
        } else if type.conforms(to: .rtf) {
            text = (try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string) ?? ""
        } else if type.conforms(to: .image) {
            text = try await recognize(try Data(contentsOf: url))
        } else {
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        return try nonEmpty(text)
    }

    static func read(image data: Data) async throws -> String {
        try nonEmpty(try await recognize(data))
    }

    private static func nonEmpty(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { throw Failure.noText }
        return trimmed
    }

    private static func recognize(_ data: Data) async throws -> String {
        guard let image = UIImage(data: data)?.cgImage else { throw Failure.noText }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}
