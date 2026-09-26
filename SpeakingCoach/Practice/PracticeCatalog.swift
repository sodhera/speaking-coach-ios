import Foundation

/// One rehearsal from `practice-content.json` — the same file the server
/// grades against, bundled unchanged so ids and versions always agree.
struct PracticeDefinition: Codable, Identifiable, Hashable {
    // Memberwise init stays available: custom situations build one in code.
    struct Criterion: Codable, Hashable {
        let id: String
        let label: String

        /// The label as a name. Rubric labels are written as sentences
        /// ("Establish the situation briefly."), and a row or tag reads
        /// better without the full stop.
        var name: String {
            guard let last = label.last, ".。".contains(last) else { return label }
            return String(label.dropLast())
        }
    }

    let id: String
    let version: Int
    let rubricVersion: String
    let scenarioId: String
    let title: String
    let category: String
    let format: String
    let durationMinutes: Int
    let partner: String
    let objective: String
    let opening: String
    let criteria: [Criterion]
    let beats: [String]
    let scaffold: String
    let transfer: String
    let maxUserTurns: Int
    let recovery: [String]
    let variants: [String]
    /// The language `opening` is written in. When it's the session's, the
    /// partner can say it the moment the room connects.
    var openingLanguage: String? = "en"

    /// The same session in the app's language. What people read (the title,
    /// the partner, the goal and the tips) is translated; the stage
    /// directions the partner is given stay as written, since it follows
    /// them in any language.
    func localized() -> PracticeDefinition {
        PracticeDefinition(
            id: id, version: version, rubricVersion: rubricVersion, scenarioId: scenarioId,
            title: CatalogText.text(title), category: category, format: format, durationMinutes: durationMinutes,
            partner: CatalogText.text(partner), objective: CatalogText.text(objective), opening: CatalogText.text(opening),
            criteria: criteria.map { Criterion(id: $0.id, label: CatalogText.text($0.label)) },
            beats: beats, scaffold: CatalogText.text(scaffold), transfer: CatalogText.text(transfer),
            maxUserTurns: maxUserTurns, recovery: recovery, variants: variants,
            openingLanguage: AppLanguage.code == "en" || CatalogText.isTranslated(opening) ? AppLanguage.code : "en"
        )
    }
}

extension PracticeDefinition {
    /// "A hiring manager · 4 min", wherever a session is listed.
    var meta: String {
        String(localized: "\(partner) · \(durationMinutes) min", bundle: AppLanguage.bundle, comment: "Who the practice partner plays, then the session's length.")
    }
}

enum PracticeCatalog {
    private static let source: [PracticeDefinition] = {
        guard let url = Bundle.main.url(forResource: "practice-content", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([PracticeDefinition].self, from: data)
        else {
            assertionFailure("practice-content.json is missing or malformed")
            return []
        }
        return items
    }()

    nonisolated(unsafe) private static var cache: (language: String, items: [PracticeDefinition])?

    /// Every session, in the app's current language.
    static var all: [PracticeDefinition] {
        let language = AppLanguage.code
        if let cache, cache.language == language { return cache.items }
        let items = source.map { $0.localized() }
        cache = (language, items)
        return items
    }

    static func definition(_ id: String) -> PracticeDefinition? {
        all.first { $0.id == id }
    }
}

/// Written content (session titles, goals, tips) translated in the
/// `Content` strings table, keyed by its English text.
enum CatalogText {
    static func text(_ english: String) -> String {
        english.isEmpty ? english : Bundle.main.localizedString(forKey: english, value: english, table: "Content")
    }

    static func isTranslated(_ english: String) -> Bool {
        !english.isEmpty && text(english) != english
    }
}
