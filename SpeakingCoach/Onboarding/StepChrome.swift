import SwiftUI

/// Fades a piece of a reveal in after a delay — the building block of every
/// staged reveal. Under Reduce Motion it appears at once.
struct RevealIn: ViewModifier {
    let delay: Double
    var rise: CGFloat = 10
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : rise)
            .task {
                if reduceMotion { shown = true; return }
                try? await Task.sleep(for: .seconds(delay))
                withAnimation(.easeOut(duration: 0.55)) { shown = true }
            }
    }
}

extension View {
    func revealIn(after delay: Double, rise: CGFloat = 10) -> some View {
        modifier(RevealIn(delay: delay, rise: rise))
    }

    /// Calls `action` once, after `delay` — how a reveal says "I've landed;
    /// the Continue button may appear now".
    func after(_ delay: Double, perform action: @escaping () -> Void) -> some View {
        modifier(AfterDelay(delay: delay, action: action))
    }
}

private struct AfterDelay: ViewModifier {
    let delay: Double
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : delay))
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
