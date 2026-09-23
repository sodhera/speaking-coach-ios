import DeviceActivity
import Foundation
import ManagedSettings

/// "Speak to unlock", as the app and its three Screen Time extensions share
/// it. Each extension runs in its own sandboxed process, so everything they
/// agree on lives in the App Group defaults and is read through here.
///
/// The rule is simple and has one direction of safety: inside the chosen
/// window, on a chosen day, with no unlock running, the chosen apps are
/// shielded. Everything else clears.
enum RoutineShared {
    static let appGroup = "group.com.sodhera.speakingcoach"
    static let deepLink = URL(string: "com.sodhera.speakingcoach://unlock")!

    static let scheduleActivity = DeviceActivityName("speakingcoach.routine.window")
    static let grantActivity = DeviceActivityName("speakingcoach.routine.grant-end")
    static let storeName = ManagedSettingsStore.Name("speakingcoach.routine")

    enum Key {
        static let selection = "routine.selection"
        static let enabled = "routine.enabled"
        static let startMinutes = "routine.startMinutes"
        static let endMinutes = "routine.endMinutes"
        static let days = "routine.days"
        static let unlockMinutes = "routine.unlockMinutes"
        static let grantExpiresAt = "routine.grantExpiresAt"
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static var isEnabled: Bool { defaults?.bool(forKey: Key.enabled) == true }

    static var unlockMinutes: Int {
        let stored = defaults?.integer(forKey: Key.unlockMinutes) ?? 0
        return stored == 0 ? 15 : stored
    }

    static var grantExpiresAt: Date? {
        guard let date = defaults?.object(forKey: Key.grantExpiresAt) as? Date, date > .now else { return nil }
        return date
    }

    /// Whether `now` falls in the window on a chosen day. A window that
    /// crosses midnight belongs to the day it started on.
    static func isInWindow(start: Int, end: Int, days: [Int], at now: Date = .now, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: now)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let today = parts.weekday ?? 1
        let yesterday = today == 1 ? 7 : today - 1
        if start == end { return days.contains(today) }
        if start < end { return days.contains(today) && minutes >= start && minutes < end }
        // Overnight: the evening half is today's; the early-morning half is yesterday's.
        return (days.contains(today) && minutes >= start) || (days.contains(yesterday) && minutes < end)
    }

    static func shouldShield(at now: Date = .now) -> Bool {
        guard let defaults, isEnabled else { return false }
        if grantExpiresAt != nil { return false }
        let days = defaults.array(forKey: Key.days) as? [Int] ?? []
        return isInWindow(start: defaults.integer(forKey: Key.startMinutes), end: defaults.integer(forKey: Key.endMinutes), days: days, at: now)
    }

    static func clearShield() {
        let store = ManagedSettingsStore(named: storeName)
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }
}
