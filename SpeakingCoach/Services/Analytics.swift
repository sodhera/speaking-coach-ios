import Foundation
import PostHog
import Supabase

/// First-party funnel analytics into Supabase and PostHog. Supabase receives
/// page, duration, and action events. PostHog also receives allowlisted,
/// bounded onboarding choices and product events (sessions, feedback,
/// purchases), keyed to the account's opaque id. Neither receives names,
/// emails, free text, or speech.
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

    /// PostHog is configured only when a project token is supplied at build
    /// time. App lifecycle events (installed, updated, opened, backgrounded)
    /// are captured; automatic interaction, screen and replay capture stay
    /// off, since they could pick up what people type.
    static func configurePostHog() {
        let token = AppConfig.postHogProjectToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        let config = PostHogConfig(projectToken: token, host: AppConfig.postHogHost)
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.captureApplicationLifecycleEvents = true
        config.sessionReplay = false
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(["app_language": AppLanguage.code])
    }

    private static var isReviewRun: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-review") || $0 == "-fresh-start" || $0 == "-zara-demo" }
        #else
        false
        #endif
    }

    /// Ties events to the account's opaque id, with the few fixed answers
    /// that segment the funnel. Nil (signed out) starts a fresh anonymous id.
    static func identify(userID: UUID?, profile: CoachProfile?) {
        guard !isReviewRun else { return }
        guard let userID else {
            PostHogSDK.shared.reset()
            PostHogSDK.shared.register(["app_language": AppLanguage.code])
            return
        }
        var properties: [String: Any] = ["language": AppLanguage.code]
        if let moment = profile?.moment { properties["moment"] = moment.rawValue }
        if let readiness = profile?.readiness { properties["readiness_baseline"] = min(max(readiness, 0), 10) }
        if let source = profile?.heardFrom { properties["heard_from"] = source.rawValue }
        if profile?.isLegacy == true { properties["legacy_account"] = true }
        PostHogSDK.shared.identify(userID.uuidString.lowercased(), userProperties: properties)
    }

    /// A product event. Callers pass only fixed values: enum raw values,
    /// catalog ids, bounded numbers and flags, never anything a person typed
    /// or said.
    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        guard !isReviewRun else { return }
        var properties = properties
        properties["visit_id"] = visitID.uuidString
        PostHogSDK.shared.capture(event, properties: properties)
    }

    static func languageChosen(_ code: String, from source: String) {
        PostHogSDK.shared.register(["app_language": code])
        capture("language_chosen", ["language": code, "previous": AppLanguage.chosen ?? "none", "source": source])
    }

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

    /// A fixed-choice onboarding response. Callers pass only enum raw values
    /// or the bounded 0...10 readiness score, never user-entered content.
    static func onboardingChoice(
        page: String,
        field: String,
        value: String,
        selected: Bool? = nil,
        context: String? = nil,
        event: String = "onboarding_choice",
        step: Int
    ) {
        guard !isReviewRun else { return }
        var properties: [String: Any] = [
            "page_id": String(page.lowercased().prefix(48)),
            "step_index": min(max(step, 0), 19),
            "choice_field": String(field.prefix(48)),
            "choice_value": String(value.prefix(48)),
            "visit_id": visitID.uuidString
        ]
        if let selected { properties["selected"] = selected }
        if let context { properties["context"] = String(context.prefix(48)) }
        PostHogSDK.shared.capture(event, properties: properties)
    }

    static func leaveCurrent() {
        guard let current else { return }
        let ms = Int(Date.now.timeIntervalSince(current.since) * 1000)
        queue(page: current.page, type: "leave", step: current.step, duration: min(ms, 86_400_000))
        self.current = nil
    }

    private static func queue(page: String, type: String, step: Int?, duration: Int? = nil) {
        // Keep simulator review runs and UI tests out of the real funnel.
        guard !isReviewRun else { return }
        let pageID = String(page.lowercased().prefix(48))
        let stepIndex = step.map { min(max($0, 0), 19) }
        pending.append(Event(
            id: UUID(),
            install_id: installID,
            visit_id: visitID,
            user_id: Backend.supabase.auth.currentUser?.id,
            page_id: pageID,
            event_type: type,
            duration_ms: duration,
            step_index: stepIndex,
            occurred_at: ISO8601DateFormatter().string(from: .now)
        ))
        var properties: [String: Any] = [
            "page_id": pageID,
            "event_type": type,
            "visit_id": visitID.uuidString
        ]
        if let stepIndex { properties["step_index"] = stepIndex }
        if let duration { properties["duration_ms"] = duration }
        PostHogSDK.shared.capture("product_page_\(type)", properties: properties)
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
