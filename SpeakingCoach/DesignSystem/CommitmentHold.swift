import SwiftUI

/// A fingerprint you hold, not a capsule you press.
///
/// Borrowed from Touch ID on purpose: people know what holding a fingerprint
/// means, so the commitment reads as something you *authorise* rather than
/// something you click past. The print fills from the bottom over two
/// seconds, a scan line rides the top of the fill, a ring closes around it,
/// and a tick every 20% reads like a scanner reading ridges. Releasing early
/// **rewinds** rather than snapping to zero — a hard reset reads as
/// punishment for a slip. Cancels on release, drag-away and backgrounding;
/// fires once.
///
/// The mark is Material Symbols `fingerprint` at weight 100 (CREDITS.md) —
/// not SF Symbols' `touchid`, which Apple licenses only for Touch ID itself.
struct CommitmentHoldButton: View {
    let action: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var progress: Double = 0
    @State private var isPressing = false
    @State private var done = false
    @State private var pulse = false
    @State private var task: Task<Void, Never>?
    @State private var lastTick = 0

    private let holdDuration = 2.0
    private let printSize: CGFloat = 96

    private var caption: String {
        if done { return String(localized: "Committed", bundle: AppLanguage.bundle) }
        return isPressing ? String(localized: "Keep holding…", bundle: AppLanguage.bundle) : String(localized: "Hold to commit", bundle: AppLanguage.bundle)
    }

    var body: some View {
        VStack(spacing: Space.xl) {
            print
            Text(caption)
                .font(Typeface.label(16))
                .foregroundStyle(done ? Palette.coralDeep : Palette.dim)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: caption)
        }
        .frame(maxWidth: .infinity)
        .onDisappear { cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
    }

    private var print: some View {
        ZStack {
            // The ring sweeps in from nothing rather than over a static
            // track, which at rest was just a hoop around the mark.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [Palette.coral, Palette.peach], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: printSize + 44, height: printSize + 44)
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(Color.white.opacity(isPressing ? 0.75 : 0.5))
                .frame(width: printSize + 24, height: printSize + 24)
                .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))

            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: printSize * 0.44, weight: .light))
                    .foregroundStyle(Palette.coral)
            } else {
                mark(Palette.muted)
                mark(LinearGradient(colors: [Palette.coral, Palette.peach], startPoint: .bottom, endPoint: .top))
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: printSize * 0.86 * progress)
                    }
                if progress > 0.02, progress < 0.99 {
                    Capsule()
                        .fill(Palette.coral)
                        .frame(width: printSize * 0.86, height: 1.5)
                        .shadow(color: Palette.coral.opacity(0.8), radius: 5)
                        .offset(y: (printSize * 0.86 / 2) - (printSize * 0.86 * progress))
                }
            }
        }
        .frame(width: printSize + 44, height: printSize + 44)
        .scaleEffect(done ? 1.03 : (isPressing ? 0.97 : 1))
        .animation(.spring(response: 0.34, dampingFraction: 0.7), value: done)
        .animation(.easeOut(duration: 0.18), value: isPressing)
        .overlay {
            if done, !reduceMotion {
                Circle()
                    .stroke(Palette.coral.opacity(pulse ? 0 : 0.5), lineWidth: 2)
                    .scaleEffect(pulse ? 1.5 : 1)
                    .frame(width: printSize + 44, height: printSize + 44)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // A drag away from the print is a cancel, not a hold.
                    if abs(value.translation.width) > 60 || abs(value.translation.height) > 60 {
                        cancel()
                        return
                    }
                    begin()
                }
                .onEnded { _ in cancel() }
        )
        .accessibilityElement()
        .accessibilityLabel("Hold to commit")
        .accessibilityHint("Double-tap to commit to your plan.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
    }

    private func mark(_ style: some ShapeStyle) -> some View {
        Image("FingerprintMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: printSize * 0.86, height: printSize * 0.86)
            .foregroundStyle(style)
    }

    private func begin() {
        guard task == nil, !done else { return }
        isPressing = true
        lastTick = 0
        Haptics.soft()
        task = Task { @MainActor in
            do {
                let step = 0.02
                while progress < 1 {
                    try await Task.sleep(for: .milliseconds(Int(step * 1000)))
                    progress = min(1, progress + step / holdDuration)
                    let tick = Int(progress * 5)
                    if tick > lastTick {
                        lastTick = tick
                        Haptics.tick(0.5 + 0.5 * progress)
                    }
                }
                complete()
            } catch {}
        }
    }

    private func cancel() {
        guard !done else { return }
        task?.cancel()
        task = nil
        isPressing = false
        lastTick = 0
        withAnimation(.easeOut(duration: 0.4)) { progress = 0 }
    }

    private func complete() {
        guard !done else { return }
        task?.cancel()
        task = nil
        progress = 1
        done = true
        isPressing = false
        Haptics.doubleHeavy()
        // A frame later, so the ring exists unexpanded before it expands.
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.7)) { pulse = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { action() }
    }
}
