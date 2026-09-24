import Foundation
import Observation
import Supabase

/// One finished rehearsal, read from the existing `reports` table (which the
/// old app wrote too, so a returning user's history comes with them).
struct PracticeRecord: Identifiable, Equatable {
    let id: UUID
    /// The catalog id it was rehearsed from; nil for old-app reports.
    let activityID: String?
    let title: String
    let date: Date
    let score: Int?
    /// Set when this record is a focused retry of another rehearsal.
    let parentID: UUID?
    /// Each rubric criterion and the level it reached, in rubric order. A
    /// retry carries only the one it targeted. Empty for custom situations
    /// and old-app reports, which have no rubric.
    var criteria: [CriterionLevel] = []
    /// A situation the user described themselves, or a built-in scene.
    var isCustom = false
}

/// A criterion's level without its note and quotes: all a record needs.
struct CriterionLevel: Decodable, Equatable {
    let id: String
    /// 0 not yet observed, 1 partly, 2 clearly demonstrated.
    let level: Int
}

@MainActor
@Observable
final class PracticeHistory {
    private(set) var records: [PracticeRecord] = []
    private(set) var loaded = false
    private(set) var userID: UUID?

    func reset() {
        records = []
        loaded = false
        userID = nil
    }

    func load(userID: UUID) async {
        self.userID = userID
        do {
            let rows: [Row] = try await Backend.supabase.from("reports")
                .select("id, scenario_id, score, created_at, activityId:analysis->practiceContext->>activityId, parentId:analysis->practiceContext->retry->>parentAttemptId, customTitle:analysis->custom->>title, criteria:analysis->practice->criteria")
                .eq("user_id", value: userID)
                .neq("scenario_id", value: "feedback")
                .order("created_at", ascending: false)
                .limit(60)
                .execute()
                .value
            guard self.userID == userID else { return }
            records = rows.map(\.record)
        } catch {
            AppLog.error("History load failed: \(error.localizedDescription)")
        }
        loaded = true
    }

    /// Consecutive days with a rehearsal, counting back from today — or from
    /// yesterday, so a streak isn't shown as broken before today is over.
    var streak: Int {
        let calendar = Calendar.current
        let days = Set(records.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: .now)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    #if DEBUG
    func setReviewRecords(_ records: [PracticeRecord]) {
        self.records = records
        loaded = true
    }
    #endif

    /// Rehearsals whose one focused retry has already been used — the server
    /// allows exactly one per rehearsal.
    var retriedIDs: Set<UUID> { Set(records.compactMap(\.parentID)) }

    /// A full saved report, for reopening a past rehearsal.
    func report(id: UUID) async throws -> PracticeReport {
        try await Backend.supabase.from("reports")
            .select("id, transcript, analysis")
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    private struct Row: Decodable {
        let id: UUID
        let scenario_id: String
        let score: Int?
        let created_at: Date
        let activityId: String?
        let parentId: String?
        let customTitle: String?
        let criteria: Levels?

        var record: PracticeRecord {
            let title = customTitle ?? activityId.flatMap { PracticeCatalog.definition($0)?.title }
                ?? scenario_id.replacingOccurrences(of: "_", with: " ").capitalized
            return PracticeRecord(
                id: id, activityID: activityId, title: title, date: created_at,
                score: (score ?? 0) > 0 ? score : nil,
                parentID: parentId.flatMap(UUID.init(uuidString:)),
                criteria: criteria?.items ?? [],
                isCustom: customTitle != nil
            )
        }
    }

    /// Tolerates an odd rubric: one malformed report mustn't cost the
    /// whole history, so it reads as having no levels instead.
    private struct Levels: Decodable {
        let items: [CriterionLevel]

        init(from decoder: Decoder) throws {
            items = (try? [CriterionLevel](from: decoder)) ?? []
        }
    }
}
