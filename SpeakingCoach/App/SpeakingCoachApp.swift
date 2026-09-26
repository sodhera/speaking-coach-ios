import SwiftUI
import UserNotifications

@main
struct SpeakingCoachApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppLanguage.install()
        Analytics.configurePostHog()
        Haptics.prepare()
        #if DEBUG
        if LaunchFlags.has("-fresh-start") {
            UserDefaults.standard.removeObject(forKey: "sc.onboardingDraft.v1")
            AppLanguage.forget()
        }
        if let language = LaunchFlags.value("-language") { AppLanguage.choose(language) }
        assert(Typeface.isAvailable, "DM Sans failed to load — the app is silently rendering in San Francisco.")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Routes taps on the app's own notifications — the daily prompt and a
/// shield's "Open Speaking Coach" — to the link they carry.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let link = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: link) else { return }
        await MainActor.run { DeepLinks.shared.pending = url }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// The app's language as SwiftUI observes it. Changing it re-renders every
/// screen in the new language at once.
@MainActor
@Observable
final class LanguageState {
    static let shared = LanguageState()
    private(set) var code = AppLanguage.code
    private(set) var isChosen = AppLanguage.chosen != nil

    func choose(_ code: String) {
        guard AppLanguage.supported.contains(code) else { return }
        AppLanguage.choose(code)
        self.code = code
        isChosen = true
    }
}

/// The one link waiting to be opened, set by a notification tap or a URL.
@MainActor
@Observable
final class DeepLinks {
    static let shared = DeepLinks()
    var pending: URL?
}
