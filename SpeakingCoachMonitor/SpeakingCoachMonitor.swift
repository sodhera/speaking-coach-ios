import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Puts the shield up when the practice window opens or an unlock runs out,
/// and takes it down when the window closes. The app reconciles the same
/// rule whenever it comes to the foreground, so a missed callback costs
/// minutes, never a lockout.
final class SpeakingCoachMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == RoutineShared.grantActivity {
            RoutineShared.defaults?.removeObject(forKey: RoutineShared.Key.grantExpiresAt)
            DeviceActivityCenter().stopMonitoring([RoutineShared.grantActivity])
        }
        if RoutineShared.shouldShield() { applyShield() }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Only the window's end lifts the shield; an unlock's tail is a no-op.
        guard activity == RoutineShared.scheduleActivity else { return }
        if !RoutineShared.shouldShield() { RoutineShared.clearShield() }
    }

    private func applyShield() {
        guard let data = RoutineShared.defaults?.data(forKey: RoutineShared.Key.selection),
              let selection = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data) else { return }
        let store = ManagedSettingsStore(named: RoutineShared.storeName)
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }
}
