import Foundation
import Observation
import PDFKit
import UIKit

// MARK: - Models

/// Who the talk is for and how hard the audience should push — it shapes
/// the questions they ask afterwards.
struct PresentationBrief: Codable, Equatable {
    enum QuestionStyle: String, Codable, CaseIterable { case supportive, curious, challenging }

    var audience = ""
    var purpose = ""
    var instructions = ""
    var questionStyle: QuestionStyle = .curious
}

struct PresentationDeck: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    let fileName: String
    let slideCount: Int
    /// Each slide's own text, for grounding the audience's questions.
    let slideTexts: [String]
    var brief = PresentationBrief()
}

struct SlideEvent: Codable, Equatable {
    /// Zero-based slide shown from this moment.
    let slideIndex: Int
    let atMs: Int
}

struct AudienceQuestion: Codable, Equatable, Identifiable {
    let id: String
    let question: String
    let reason: String
    let slideIndex: Int?

    private enum CodingKeys: String, CodingKey { case id, question, reason, slideIndex }

    /// The server needs `slideIndex` present even when it's null.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(question, forKey: .question)
        try container.encode(reason, forKey: .reason)
        try container.encode(slideIndex, forKey: .slideIndex)
    }
}

struct QuestionAnswer: Codable, Equatable {
    let questionId: String
    let transcript: String
    let feedback: String
}

struct PresentationRehearsal: Codable, Equatable, Identifiable {
    let id: UUID
    let deckID: UUID
    let startedAt: Date
    let durationMs: Int
    let audioFile: String
    var transcript: String
    let slideEvents: [SlideEvent]
    var questions: [AudienceQuestion]
    var answers: [QuestionAnswer]

    /// The slide on screen at a moment of the recording.
    func slide(atMs ms: Int) -> Int {
        slideEvents.last { $0.atMs <= ms }?.slideIndex ?? 0
    }
}

// MARK: - Store

/// Decks, their PDFs, recordings and rehearsals live on this device only,
/// in Application Support with complete file protection. Only what coaching
/// needs — the transcript, slide text, a recorded answer — ever leaves it.
@MainActor
@Observable
final class PresentationStore {
    private(set) var decks: [PresentationDeck] = []
    private(set) var rehearsals: [UUID: [PresentationRehearsal]] = [:]

    private let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appending(path: "Presentations", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private var decksFile: URL { root.appending(path: "decks.json") }
    func folder(for deck: UUID) -> URL { root.appending(path: deck.uuidString, directoryHint: .isDirectory) }
    func pdfURL(for deck: UUID) -> URL { folder(for: deck).appending(path: "deck.pdf") }
    func audioURL(_ rehearsal: PresentationRehearsal) -> URL { folder(for: rehearsal.deckID).appending(path: rehearsal.audioFile) }
    private func rehearsalsFile(_ deck: UUID) -> URL { folder(for: deck).appending(path: "rehearsals.json") }

    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    init() { load() }

    func load() {
        decks = (try? decoder.decode([PresentationDeck].self, from: Data(contentsOf: decksFile))) ?? []
        decks.sort { $0.updatedAt > $1.updatedAt }
        for deck in decks {
            rehearsals[deck.id] = (try? decoder.decode([PresentationRehearsal].self, from: Data(contentsOf: rehearsalsFile(deck.id)))) ?? []
        }
    }

    // MARK: Import

    enum ImportError: LocalizedError {
        case unreadable, empty, tooLarge
        var errorDescription: String? {
            switch self {
            case .unreadable: "That file couldn't be opened as a presentation. Export it as a PDF and try again."
            case .empty: "That PDF has no pages."
            case .tooLarge: "That presentation is over 100 slides. Try a shorter version."
            }
        }
    }

    /// Adds a deck from a PDF's data. PowerPoint files are converted to PDF
    /// by the server first (see `PresentationAPI.convert`).
    func importPDF(_ data: Data, fileName: String) throws -> PresentationDeck {
        guard let document = PDFDocument(data: data) else { throw ImportError.unreadable }
        guard document.pageCount > 0 else { throw ImportError.empty }
        guard document.pageCount <= 100 else { throw ImportError.tooLarge }
        let texts = (0..<document.pageCount).map { index in
            String((document.page(at: index)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        }
        let title = (fileName as NSString).deletingPathExtension
        let deck = PresentationDeck(
            id: UUID(), title: title.isEmpty ? "Presentation" : title, createdAt: .now, updatedAt: .now,
            fileName: fileName, slideCount: document.pageCount, slideTexts: texts
        )
        try FileManager.default.createDirectory(at: folder(for: deck.id), withIntermediateDirectories: true)
        try data.write(to: pdfURL(for: deck.id), options: [.atomic, .completeFileProtection])
        decks.insert(deck, at: 0)
        rehearsals[deck.id] = []
        try persistDecks()
        return deck
    }

    func update(_ deck: PresentationDeck) {
        guard let index = decks.firstIndex(where: { $0.id == deck.id }) else { return }
        var updated = deck
        updated.updatedAt = .now
        decks[index] = updated
        try? persistDecks()
    }

    func delete(_ deck: PresentationDeck) {
        try? FileManager.default.removeItem(at: folder(for: deck.id))
        decks.removeAll { $0.id == deck.id }
        rehearsals[deck.id] = nil
        try? persistDecks()
    }

    func save(_ rehearsal: PresentationRehearsal) {
        var list = rehearsals[rehearsal.deckID] ?? []
        list.removeAll { $0.id == rehearsal.id }
        list.insert(rehearsal, at: 0)
        rehearsals[rehearsal.deckID] = list
        if let data = try? encoder.encode(list) {
            try? data.write(to: rehearsalsFile(rehearsal.deckID), options: [.atomic, .completeFileProtection])
        }
    }

    private func persistDecks() throws {
        try encoder.encode(decks).write(to: decksFile, options: [.atomic, .completeFileProtection])
    }

    // MARK: Slides

    private var documents: [UUID: PDFDocument] = [:]
    private let renders = NSCache<NSString, UIImage>()

    /// A slide rendered for display, cached by size.
    func image(deck: UUID, slide: Int, width: CGFloat) -> UIImage? {
        let key = "\(deck)-\(slide)-\(Int(width))" as NSString
        if let cached = renders.object(forKey: key) { return cached }
        let document = documents[deck] ?? PDFDocument(url: pdfURL(for: deck))
        documents[deck] = document
        guard let page = document?.page(at: slide) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = UIScreen.main.scale
        let size = CGSize(width: width * scale, height: width * scale * bounds.height / max(bounds.width, 1))
        let image = page.thumbnail(of: size, for: .mediaBox)
        renders.setObject(image, forKey: key)
        return image
    }
}
