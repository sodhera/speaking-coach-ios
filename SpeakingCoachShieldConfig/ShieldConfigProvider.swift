import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen someone meets when they reach for a blocked app: the bloom on
/// the morning cream, one line that says what unlocks it, and the way in.
/// A shield is rendered by the system from this static description, so it
/// carries only the bundled bloom image and the app's colours.
final class ShieldConfigProvider: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration { make(noun: "this app") }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { make(noun: "this app") }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { make(noun: "this site") }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { make(noun: "this site") }

    private static let cream = UIColor(red: 0xFF / 255, green: 0xFB / 255, blue: 0xF7 / 255, alpha: 1)
    private static let coral = UIColor(red: 0xFF / 255, green: 0x5A / 255, blue: 0x5F / 255, alpha: 1)
    private static let ink = UIColor(red: 0x23 / 255, green: 0x1A / 255, blue: 0x1B / 255, alpha: 1)
    private static let dim = UIColor(red: 0x6B / 255, green: 0x5A / 255, blue: 0x5B / 255, alpha: 1)

    private func make(noun: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialLight,
            backgroundColor: Self.cream,
            icon: UIImage(named: "ShieldBloom"),
            title: .init(text: "Speak to unlock", color: Self.ink),
            subtitle: .init(text: "Say one thing out loud in Speaking Coach to open \(noun) for \(RoutineShared.unlockMinutes) minutes.", color: Self.dim),
            primaryButtonLabel: .init(text: "Open Speaking Coach", color: .white),
            primaryButtonBackgroundColor: Self.coral,
            secondaryButtonLabel: .init(text: "Not now", color: Self.dim)
        )
    }
}
