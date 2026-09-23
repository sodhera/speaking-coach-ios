import Foundation
import Supabase

/// First-party funnel analytics into the existing `product_page_events`
/// table: which screen was entered, for how long, and whether its action was
/// taken. The table has no column for answers, names or free text — by design
/// nothing personal can be written, and that is the point.
///
/// Onboarding pages are named `ob_<step>` with the step's index, so drop-off
/// reads straight off the funnel.
@MainActor
enum Analytics {
    private static let installID: UUID = {
        let key = "sc.installID"
        if let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }()

    private static let visitID = UUID()
    private static var current: (page: String, step: Int?, since: Date)?
    private static var pending: [Event] = []
    private static var flushTask: Task<Void, Never>?

    /// Records entering a page, closing the previous one with its duration.
    static func enter(_ page: String, step: Int? = nil) {
        guard current?.page != page else { return }
        leaveCurrent()
        current = (page, step, .now)
        queue(page: page, type: "enter", step: step)
    }

    /// The page's primary action was taken (Continue, a purchase, a start).
    static func action(_ page: String, step: Int? = nil) {
        queue(page: page, type: "action", step: step)
    }

    static func leaveCurrent() {
        guard let current else { return }
        let ms = Int(Date.now.timeIntervalSince(current.since) * 1000)
        queue(page: current.page, type: "leave", step: current.step, duration: min(ms, 86_400_000))
        self.current = nil
    }

    private static func queue(page: String, type: String, step: Int?, duration: Int? = nil) {
        #if DEBUG
        // Keep simulator review runs and UI tests out of the real funnel.
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-review") || $0 == "-fresh-start" }) { return }
        #endif
        pending.append(Event(
            id: UUID(),
            install_id: installID,
            visit_id: visitID,
            user_id: Backend.supabase.auth.currentUser?.id,
            page_id: String(page.lowercased().prefix(48)),
            event_type: type,
            duration_ms: duration,
            step_index: step.map { min(max($0, 0), 19) },
            occurred_at: ISO8601DateFormatter().string(from: .now)
        ))
        scheduleFlush()
    }

    private static func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task {
            try? await Task.sleep(for: .seconds(4))
            let batch = pending
            pending.removeAll()
            flushTask = nil
            guard !batch.isEmpty else { return }
            do {
                try await Backend.supabase.from("product_page_events").insert(batch).execute()
            } catch {
                AppLog.error("Analytics flush failed: \(error.localizedDescription)")
            }
        }
    }

    private struct Event: Encodable {
        let id: UUID
        let install_id: UUID
        let visit_id: UUID
        let user_id: UUID?
        let page_id: String
        let event_type: String
        let duration_ms: Int?
        let step_index: Int?
        let occurred_at: String
    }
}
