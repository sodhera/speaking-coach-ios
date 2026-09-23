import ManagedSettings
import UserNotifications

/// A shield can't open another app, so "Open Speaking Coach" posts a
/// notification whose tap lands on today's prompt — the same bridge
/// SleepBlock uses. "Not now" just closes the shield.
final class ShieldActionHandler: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler)
    }

    private func respond(to action: ShieldAction, _ completionHandler: @escaping (ShieldActionResponse) -> Void) {
        if action == .primaryButtonPressed {
            let content = UNMutableNotificationContent()
            content.title = "Speak to unlock"
            content.body = "Tap for today's prompt. One sentence, out loud."
            content.sound = .default
            content.userInfo = ["url": RoutineShared.deepLink.absoluteString]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "sc.routine.unlock", content: content, trigger: nil))
        }
        completionHandler(.close)
    }
}
