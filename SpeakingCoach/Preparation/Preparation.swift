import Foundation
import Observation
import Supabase
import UserNotifications

/// A short run of rehearsals chosen for one kind of moment, optionally
/// aimed at a date.
struct PreparationProgram: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let practiceIDs: [String]

    var practices: [PracticeDefinition] { practiceIDs.compactMap(PracticeCatalog.definition) }

    static let all: [PreparationProgram] = [
        PreparationProgram(id: "interview", title: "Get ready for an interview", detail: "Your opening, your experience, and the follow-ups.", icon: "briefcase.fill",
                           practiceIDs: ["interview_tell_me_about_yourself", "interview_evidence", "interview_pressure", "ask_for_clarity", "pitch_big_idea"]),
        PreparationProgram(id: "work", title: "Be clearer at work", detail: "Updates, questions, and speaking up in meetings.", icon: "person.3.fill",
                           practiceIDs: ["clear_work_update", "ask_for_clarity", "explain_a_mistake", "disagree_in_meeting", "presentation_opening"]),
        PreparationProgram(id: "boundaries", title: "Hold your ground", detail: "Ask for what you want and stay steady under pushback.", icon: "hand.raised.fill",
                           practiceIDs: ["salary_raise", "set_a_boundary", "disagree_in_meeting", "ask_for_clarity", "interview_pressure"]),
        PreparationProgram(id: "everyday", title: "Feel easier in conversation", detail: "Introductions, small talk, and saying what you mean.", icon: "bubble.left.and.bubble.right.fill",
                           practiceIDs: ["first_gentle_introduction", "meet_someone_new", "ask_for_clarity", "set_a_boundary", "presentation_opening"]),
    ]

    static func find(_ id: String) -> PreparationProgram? { all.first { $0.id == id } }

    /// The program that fits what the user told onboarding.
    static func suggested(for moment: SpeakingMoment?) -> PreparationProgram {
        let id = switch moment {
        case .interview: "interview"
        case .raise, .hardConversation: "boundaries"
        case .speakingUp, .presentation: "work"
        case .meetingPeople, .everyday, .ielts, nil: "everyday"
        }
        return find(id) ?? all[0]
    }
}

struct PreparationPlan: Codable, Equatable {
    enum Outcome: String, Codable, CaseIterable {
        case used, notYet = "not_used", didNotHappen = "did_not_happen"

        var label: String {
            switch self {
            case .used: "I used something I practised"
            case .notYet: "I haven't used it yet"
            case .didNotHappen: "It didn't happen"
            }
        }
    }

    struct Reflection: Codable, Equatable {
        var outcome: Outcome
        var note: String
        var recordedAt: Date
    }

    var programID: String
    var eventName: String
    /// The day of the event, if there is one.
    var eventDate: Date?
    var reminderEnabled: Bool
    /// Rehearsals count toward the plan from here on.
    var createdAt: Date
    var reflection: Reflection?

    var program: PreparationProgram? { PreparationProgram.find(programID) }

    /// First rehearsals (not retries) of the plan's practices since it began.
    func completedIDs(in records: [PracticeRecord]) -> Set<String> {
        let ids = Set(program?.practiceIDs ?? [])
        return Set(records.filter { record in
            guard let id = record.activityID else { return false }
            return ids.contains(id) && record.parentID == nil && record.date >= createdAt
        }.compactMap(\.activityID))
    }

    func next(in records: [PracticeRecord]) -> PracticeDefinition? {
        let done = completedIDs(in: records)
        return program?.practices.first { !done.contains($0.id) }
    }

    /// Whole days until the event: 0 on the day, negative once it's passed.
    func daysUntilEvent(from now: Date = .now) -> Int? {
        guard let eventDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: eventDate)).day
    }

    /// 9 am the day before, or 9 am on the day if that's already gone; nil
    /// when both have passed.
    static func reminderDate(for event: Date, now: Date = .now) -> Date? {
        let calendar = Calendar.current
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: event) ?? event
        if let dayBefore = calendar.date(byAdding: .day, value: -1, to: morning), dayBefore > now { return dayBefore }
        return morning > now ? morning : nil
    }
}

/// The plan lives on the account (`user_metadata.preparation_plan_v1`), so
/// it follows the user to a new phone, with a local copy for instant launch.
@MainActor
@Observable
final class PreparationStore {
    private(set) var plan: PreparationPlan?
    private var userID: UUID?

    private static let metadataKey = "preparation_plan_v1"
    private static let reminderID = "sc.preparationEvent"
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    private func cacheKey(_ id: UUID) -> String { "sc.preparation.\(id.uuidString)" }

    func load(userID: UUID) async {
        if self.userID != userID {
            self.userID = userID
            plan = UserDefaults.standard.data(forKey: cacheKey(userID)).flatMap { try? decoder.decode(PreparationPlan.self, from: $0) }
        }
        guard let user = try? await Backend.supabase.auth.user() else { return }
        if let json = user.userMetadata[Self.metadataKey] {
            if case .null = json { plan = nil } else if let data = try? encoder.encode(json) {
                plan = try? decoder.decode(PreparationPlan.self, from: data)
            }
            cache()
        }
    }

    enum SaveOutcome: Equatable { case saved, savedWithoutReminder(String) }

    /// Saves (or with nil, removes) the plan, then sets its one reminder.
    func save(_ plan: PreparationPlan?) async throws -> SaveOutcome {
        guard let userID else { throw PracticeAPIError.signedOut }
        let json: AnyJSON = try plan.map { try decoder.decode(AnyJSON.self, from: encoder.encode($0)) } ?? .null
        do {
            _ = try await Backend.supabase.auth.update(user: UserAttributes(data: [Self.metadataKey: json]))
        } catch {
            throw PracticeAPIError.server(status: 0, message: "Your plan wasn't saved. Check your connection and try again.")
        }
        self.plan = plan
        self.userID = userID
        cache()
        return await applyReminder()
    }

    #if DEBUG
    func setReviewPlan(_ plan: PreparationPlan) { self.plan = plan }
    #endif

    func clearLocal() {
        plan = nil
        userID = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
    }

    private func cache() {
        guard let userID else { return }
        if let plan, let data = try? encoder.encode(plan) {
            UserDefaults.standard.set(data, forKey: cacheKey(userID))
        } else {
            UserDefaults.standard.removeObject(forKey: cacheKey(userID))
        }
    }

    /// The lock screen never shows the event's name — only that it's close.
    private func applyReminder() async -> SaveOutcome {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
        guard let plan, plan.reminderEnabled, let event = plan.eventDate else { return .saved }
        guard let date = PreparationPlan.reminderDate(for: event) else {
            return .savedWithoutReminder("Your plan is saved. The event is too close for a 9 am reminder.")
        }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else {
            return .savedWithoutReminder("Your plan is saved, but notifications are off. Turn them on in Settings for the reminder.")
        }
        let content = UNMutableNotificationContent()
        content.title = "Your moment is close"
        content.body = "One session now makes it easier to walk in ready."
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        try? await center.add(UNNotificationRequest(identifier: Self.reminderID, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        return .saved
    }
}
