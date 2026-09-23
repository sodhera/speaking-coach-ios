import Foundation

/// One rehearsal from `practice-content.json` — the same file the server
/// grades against, bundled unchanged so ids and versions always agree.
struct PracticeDefinition: Codable, Identifiable, Hashable {
    struct Criterion: Codable, Hashable {
        let id: String
        let label: String
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
}

enum PracticeCatalog {
    static let all: [PracticeDefinition] = {
        guard let url = Bundle.main.url(forResource: "practice-content", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([PracticeDefinition].self, from: data)
        else {
            assertionFailure("practice-content.json is missing or malformed")
            return []
        }
        return items
    }()

    static func definition(_ id: String) -> PracticeDefinition? {
        all.first { $0.id == id }
    }
}
