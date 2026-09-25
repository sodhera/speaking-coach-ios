import Foundation
import Observation
import UserNotifications

/// The practice routine: a daily speaking prompt, delivered as a
/// notification at the time and on the days you choose.
@MainActor
@Observable
final class RoutineStore {
    struct Settings: Equatable {
        var promptEnabled = false
        var promptMinutes = 8 * 60
        var promptDays: [Int] = [2, 3, 4, 5, 6]
    }

    private(set) var settings = Settings()

    private static let promptKey = "sc.routine.prompt"

    init() { load() }

    func load() {
        if let prompt = UserDefaults.standard.dictionary(forKey: Self.promptKey) {
            settings.promptEnabled = prompt["enabled"] as? Bool ?? false
        }
    }

    // MARK: Daily prompt

    static let promptLink = URL(string: "com.sodhera.speakingcoach://prompt")!

    /// One notification per chosen weekday. Returns false when notifications are off.
    @discardableResult
    func setPrompt(enabled: Bool, minutes: Int, days: [Int]) async -> Bool {
        let notifications = UNUserNotificationCenter.current()
        notifications.removePendingNotificationRequests(withIdentifiers: (1...7).map { "sc.routine.prompt.\($0)" })
        settings.promptEnabled = enabled
        settings.promptMinutes = minutes
        settings.promptDays = days.sorted()
        UserDefaults.standard.set(["enabled": enabled, "minutes": minutes, "days": settings.promptDays], forKey: Self.promptKey)
        guard enabled else { return true }
        let granted = (try? await notifications.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else {
            settings.promptEnabled = false
            UserDefaults.standard.set(["enabled": false, "minutes": minutes, "days": settings.promptDays], forKey: Self.promptKey)
            return false
        }
        for day in settings.promptDays {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Today's prompt", bundle: AppLanguage.bundle)
            content.body = String(localized: "One sentence, out loud. Thirty seconds.", bundle: AppLanguage.bundle)
            content.sound = .default
            content.userInfo = ["url": Self.promptLink.absoluteString]
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60, weekday: day), repeats: true)
            try? await notifications.add(UNNotificationRequest(identifier: "sc.routine.prompt.\(day)", content: content, trigger: trigger))
        }
        return true
    }

    func clearOnSignOut() {
        Task { await setPrompt(enabled: false, minutes: settings.promptMinutes, days: settings.promptDays) }
    }

    static func clock(_ minutes: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? .now
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: AppLanguage.locale))
    }
}
