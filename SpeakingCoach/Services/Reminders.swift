import Foundation
import UserNotifications

/// One gentle daily nudge to rehearse, at 6:30 PM local — after work, before
/// the evening is gone. Local only; nothing leaves the device.
@MainActor
enum Reminders {
    private static let id = "sc.dailyRehearsal"
    private static let enabledKey = "sc.remindersEnabled"
    static let hour = 18
    static let minute = 30

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var timeLabel: String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: AppLanguage.locale))
    }

    static var authorizationStatus: UNAuthorizationStatus {
        get async { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    }

    /// Asks for permission (once), then schedules. Returns whether it's on.
    @discardableResult
    static func enable(practiceTitle: String?) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Two minutes, out loud.", bundle: AppLanguage.bundle)
        content.body = practiceTitle.map { String(localized: "Your next session: \($0).", bundle: AppLanguage.bundle) } ?? String(localized: "Your next session is ready.", bundle: AppLanguage.bundle)
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        UserDefaults.standard.set(true, forKey: enabledKey)
        return true
    }

    static func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UserDefaults.standard.set(false, forKey: enabledKey)
    }
}
