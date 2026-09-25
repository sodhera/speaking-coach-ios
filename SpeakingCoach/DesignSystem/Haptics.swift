import UIKit

/// Every button knocks `heavy()` — wired into the shared button components so
/// no call site can forget or double it. `soft()` is for non-button cues
/// (a selection, a swipe), `tick` ratchets a hold, `doubleHeavy` marks the
/// instant a commitment completes.
@MainActor
enum Haptics {
    private static let soft_ = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid_ = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy_ = UIImpactFeedbackGenerator(style: .heavy)
    private static let notify = UINotificationFeedbackGenerator()
    private static let select = UISelectionFeedbackGenerator()

    static func prepare() {
        [soft_, rigid_, heavy_].forEach { $0.prepare() }
        notify.prepare()
        select.prepare()
    }

    static func soft() { soft_.impactOccurred(); soft_.prepare() }
    static func soft(_ intensity: CGFloat) {
        soft_.impactOccurred(intensity: min(max(intensity, 0), 1))
        soft_.prepare()
    }
    static func rigid() { rigid_.impactOccurred(); rigid_.prepare() }
    static func heavy() { heavy_.impactOccurred(); heavy_.prepare() }
    static func selection() { select.selectionChanged(); select.prepare() }

    static func tick(_ intensity: CGFloat) {
        heavy_.impactOccurred(intensity: min(max(intensity, 0), 1))
        heavy_.prepare()
    }

    static func doubleHeavy() {
        heavy_.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            heavy_.impactOccurred()
            heavy_.prepare()
        }
    }

    static func success() { notify.notificationOccurred(.success); notify.prepare() }
    static func error() { notify.notificationOccurred(.error); notify.prepare() }
}
