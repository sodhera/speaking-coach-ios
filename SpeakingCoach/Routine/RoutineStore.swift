import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation
import UserNotifications

/// The practice routine: a daily speaking prompt at a time you choose, and
/// "speak to unlock" — distracting apps shielded during a window until you
/// say one thing out loud. Built on Apple's Screen Time APIs: the app never
/// learns which apps you picked, only opaque tokens.
///
/// Safety runs one way. Turning the routine off always clears the shield,
/// the app reconciles the rule every time it comes forward, and the prompt
/// has a slow-opening skip, so a failed microphone or an outage can delay
/// you by seconds but never lock you out.
@MainActor
@Observable
final class RoutineStore {
    struct Settings: Equatable {
        var unlockEnabled = false
        var startMinutes = 9 * 60
        var endMinutes = 21 * 60
        /// Calendar weekdays: 1 = Sunday … 7 = Saturday.
        var unlockDays: [Int] = [1, 2, 3, 4, 5, 6, 7]
        var unlockMinutes = 15

        var promptEnabled = false
        var promptMinutes = 8 * 60
        var promptDays: [Int] = [2, 3, 4, 5, 6]
    }

    private(set) var settings = Settings()
    private(set) var selection = FamilyActivitySelection()
    private(set) var authorization: AuthorizationStatus = .notDetermined
    private(set) var grantExpiresAt: Date?

    /// Screen Time shields need a real iPhone.
    let isSupported: Bool = {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }()

    var selectionCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    var isShieldUp: Bool { isSupported && RoutineShared.shouldShield() }

    private var group: UserDefaults { RoutineShared.defaults ?? .standard }
    private let center = DeviceActivityCenter()
    private static let promptKey = "sc.routine.prompt"

    init() { load() }

    func load() {
        let d = group
        settings.unlockEnabled = d.bool(forKey: RoutineShared.Key.enabled)
        if d.object(forKey: RoutineShared.Key.startMinutes) != nil {
            settings.startMinutes = d.integer(forKey: RoutineShared.Key.startMinutes)
            settings.endMinutes = d.integer(forKey: RoutineShared.Key.endMinutes)
            settings.unlockDays = d.array(forKey: RoutineShared.Key.days) as? [Int] ?? settings.unlockDays
        }
        settings.unlockMinutes = RoutineShared.unlockMinutes
        if let data = d.data(forKey: RoutineShared.Key.selection),
           let decoded = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = decoded
        }
        if let prompt = UserDefaults.standard.dictionary(forKey: Self.promptKey) {
            settings.promptEnabled = prompt["enabled"] as? Bool ?? false
            settings.promptMinutes = prompt["minutes"] as? Int ?? settings.promptMinutes
            settings.promptDays = prompt["days"] as? [Int] ?? settings.promptDays
        }
        grantExpiresAt = RoutineShared.grantExpiresAt
        if isSupported { authorization = AuthorizationCenter.shared.authorizationStatus }
    }

    // MARK: Speak to unlock

    enum RoutineError: LocalizedError {
        case unsupported, notAuthorized, noSelection, noDays
        var errorDescription: String? {
            switch self {
            case .unsupported: "Speak to unlock needs Screen Time on a real iPhone."
            case .notAuthorized: "Allow Screen Time access first. Speaking Coach never sees which apps you choose."
            case .noSelection: "Choose at least one app to shield."
            case .noDays: "Choose at least one day."
            }
        }
    }

    func requestAuthorization() async throws {
        guard isSupported else { throw RoutineError.unsupported }
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        authorization = AuthorizationCenter.shared.authorizationStatus
    }

    func setSelection(_ selection: FamilyActivitySelection) {
        self.selection = selection
        if let data = try? PropertyListEncoder().encode(selection) { group.set(data, forKey: RoutineShared.Key.selection) }
        reconcile()
    }

    /// Saves the window and turns the shield schedule on.
    func enableUnlock(_ new: Settings) throws {
        guard isSupported else { throw RoutineError.unsupported }
        guard authorization == .approved else { throw RoutineError.notAuthorized }
        guard selectionCount > 0 else { throw RoutineError.noSelection }
        guard !new.unlockDays.isEmpty else { throw RoutineError.noDays }
        settings.unlockEnabled = true
        settings.startMinutes = new.startMinutes
        settings.endMinutes = new.endMinutes
        settings.unlockDays = new.unlockDays.sorted()
        settings.unlockMinutes = new.unlockMinutes
        persistUnlock()
        center.stopMonitoring([RoutineShared.scheduleActivity])
        // Repeats daily; the monitor checks the day itself, so one schedule
        // covers any set of days. Equal times mean all day.
        let end = new.endMinutes == new.startMinutes ? (new.startMinutes + 1439) % 1440 : new.endMinutes
        try center.startMonitoring(RoutineShared.scheduleActivity, during: DeviceActivitySchedule(
            intervalStart: DateComponents(hour: new.startMinutes / 60, minute: new.startMinutes % 60),
            intervalEnd: DateComponents(hour: end / 60, minute: end % 60),
            repeats: true
        ))
        reconcile()
    }

    func disableUnlock() {
        settings.unlockEnabled = false
        persistUnlock()
        group.removeObject(forKey: RoutineShared.Key.grantExpiresAt)
        grantExpiresAt = nil
        center.stopMonitoring([RoutineShared.scheduleActivity, RoutineShared.grantActivity])
        RoutineShared.clearShield()
    }

    /// Lifts the shield for the unlock span and arranges for it to return.
    func grant(minutes: Int? = nil) {
        guard settings.unlockEnabled else { return }
        let span = minutes ?? settings.unlockMinutes
        let expiry = Date.now.addingTimeInterval(TimeInterval(span * 60))
        group.set(expiry, forKey: RoutineShared.Key.grantExpiresAt)
        grantExpiresAt = expiry
        RoutineShared.clearShield()
        center.stopMonitoring([RoutineShared.grantActivity])
        // DeviceActivity needs at least a 15-minute interval; only its start
        // matters. Full date components, or a non-repeating schedule never fires.
        let calendar = Calendar.current
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        try? center.startMonitoring(RoutineShared.grantActivity, during: DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(fields, from: expiry),
            intervalEnd: calendar.dateComponents(fields, from: expiry.addingTimeInterval(20 * 60)),
            repeats: false
        ))
    }

    /// Makes the shield match the rule right now. Called whenever the app
    /// comes forward — the backstop for any callback the system skipped.
    func reconcile() {
        grantExpiresAt = RoutineShared.grantExpiresAt
        if grantExpiresAt == nil { group.removeObject(forKey: RoutineShared.Key.grantExpiresAt) }
        guard isSupported else { return }
        authorization = AuthorizationCenter.shared.authorizationStatus
        guard RoutineShared.shouldShield() else { RoutineShared.clearShield(); return }
        let store = ManagedSettingsStore(named: RoutineShared.storeName)
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    private func persistUnlock() {
        let d = group
        d.set(settings.unlockEnabled, forKey: RoutineShared.Key.enabled)
        d.set(settings.startMinutes, forKey: RoutineShared.Key.startMinutes)
        d.set(settings.endMinutes, forKey: RoutineShared.Key.endMinutes)
        d.set(settings.unlockDays, forKey: RoutineShared.Key.days)
        d.set(settings.unlockMinutes, forKey: RoutineShared.Key.unlockMinutes)
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
            content.title = "Today's prompt"
            content.body = "One sentence, out loud. Thirty seconds."
            content.sound = .default
            content.userInfo = ["url": Self.promptLink.absoluteString]
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60, weekday: day), repeats: true)
            try? await notifications.add(UNNotificationRequest(identifier: "sc.routine.prompt.\(day)", content: content, trigger: trigger))
        }
        return true
    }

    func clearOnSignOut() {
        disableUnlock()
        Task { await setPrompt(enabled: false, minutes: settings.promptMinutes, days: settings.promptDays) }
    }

    static func clock(_ minutes: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
