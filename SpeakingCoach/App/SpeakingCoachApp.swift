import SwiftUI

@main
struct SpeakingCoachApp: App {
    init() {
        Haptics.prepare()
        #if DEBUG
        if LaunchFlags.has("-fresh-start") {
            UserDefaults.standard.removeObject(forKey: "sc.onboardingDraft.v1")
        }
        assert(Typeface.isAvailable, "DM Sans failed to load — the app is silently rendering in San Francisco.")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
