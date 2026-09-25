import Foundation

/// The paywall's words, set from the current RevenueCat offering's metadata
/// so copy can change — and be A/B tested with Experiments — without an app
/// update. Every field falls back to the shipped copy; a missing, empty or
/// malformed key is ignored, never shown.
///
/// Prices, the billing footnotes and the card layout are deliberately not
/// here: they carry App Store Guideline 3.1.2(c) and stay in code.
///
/// Text may use tokens that expand to the user's own answers, so remote copy
/// keeps the personalization: `{headline}` (their outcome headline),
/// `{practice}` (their moment's practice line), `{retry}` (their pattern's
/// fix). The calls to action use `{trial}` ("1-Week") and `{plan}`
/// ("Yearly"). A field with any other `{…}` falls back, so a typo can't
/// reach the screen.
///
/// ```json
/// {
///   "headline": "{headline}",
///   "benefits": [
///     { "lead": "Practice it", "detail": "{practice}" },
///     { "lead": "Hear it back", "detail": "Feedback that quotes your own words." },
///     { "lead": "Retry the moment", "detail": "{retry}" }
///   ],
///   "plans_title": "Select a plan that fits you",
///   "reassurance": "Change plans or cancel anytime.",
///   "cta_trial": "Start {trial} Free Trial",
///   "cta": "Continue with {plan}",
///   "default_plan": "annual",
///   "show_badge": true
/// }
/// ```
struct PaywallCopy: Equatable {
    struct Benefit: Equatable {
        let lead: String
        let detail: String
    }

    var headline = "{headline}"
    var benefits = [
        Benefit(lead: "Practice it", detail: "{practice}"),
        Benefit(lead: "Hear it back", detail: "Feedback that quotes your own words."),
        Benefit(lead: "Retry the moment", detail: "{retry}"),
    ]
    var plansTitle = "Select a plan that fits you"
    var reassurance = "Change plans or cancel anytime."
    var trialCallToAction = "Start {trial} Free Trial"
    var callToAction = "Continue with {plan}"
    var preselectsAnnual = true
    /// The savings or free-trial sticker on a plan card.
    var showsBadge = true

    static let profileTokens: Set<String> = ["headline", "practice", "retry"]
    static let planTokens: Set<String> = ["trial", "plan"]

    init() {}

    init(metadata: [String: Any]) {
        func text(_ key: String, _ allowed: Set<String> = Self.profileTokens) -> String? {
            Self.valid(metadata[key], allowed: allowed)
        }
        if let value = text("headline") { headline = value }
        if let value = text("plans_title") { plansTitle = value }
        if let value = text("reassurance") { reassurance = value }
        if let value = text("cta_trial", Self.planTokens) { trialCallToAction = value }
        if let value = text("cta", Self.planTokens) { callToAction = value }

        // All or nothing: a half-parsed list would drop a benefit silently.
        if let raw = metadata["benefits"] as? [[String: Any]], (1...4).contains(raw.count) {
            let parsed = raw.compactMap { item -> Benefit? in
                guard let lead = Self.valid(item["lead"], allowed: Self.profileTokens),
                      let detail = Self.valid(item["detail"], allowed: Self.profileTokens) else { return nil }
                return Benefit(lead: lead, detail: detail)
            }
            if parsed.count == raw.count { benefits = parsed }
        }

        switch metadata["default_plan"] as? String {
        case "annual": preselectsAnnual = true
        case "monthly": preselectsAnnual = false
        default: break
        }
        if let value = metadata["show_badge"] as? Bool { showsBadge = value }
    }

    /// Non-empty text whose tokens are all known, else nil.
    private static func valid(_ value: Any?, allowed: Set<String>) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, tokens(in: text).isSubset(of: allowed) else { return nil }
        return text
    }

    /// Every `{…}` in the text, by name.
    static func tokens(in text: String) -> Set<String> {
        Set(text.matches(of: /\{([^}]*)\}/).map { String($0.output.1) })
    }

    /// Replaces each `{token}` with its value.
    static func fill(_ text: String, _ values: [String: String]) -> String {
        values.reduce(text) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }
}
