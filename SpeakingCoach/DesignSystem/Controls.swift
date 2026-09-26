import SwiftUI
import UIKit

// Shared controls, each a port of SleepBlock's equivalent into the Morning
// Stage palette. Keep the behavioural notes — each one is a bug that was
// found and fixed there first.

// MARK: - Option row

/// One full-width answer capsule, shared by every list question. Selection
/// semantics live in the caller; the row only shows state.
///
/// The selection is drawn *inside* the row's own content — a coral wash, a
/// firm coral ring, a coral icon and a solid check — never as an overlay on
/// top of the glass. SleepBlock paints its selection as an overlay to avoid
/// rebuilding the glass on each tap, but inside a `GlassEffectContainer` on
/// iOS 26 the container absorbs overlays on its children and the selection
/// all but vanishes (measured: a barely-tinted ring). Content drawn inside
/// the glass stays crisp, and the glass itself — its tint — never changes.
struct OptionRow: View {
    let icon: String?
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            HStack(spacing: Space.md) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(isSelected ? Palette.coralDeep : Palette.muted)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(Typeface.label(16))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Space.sm)
                SelectionCheck(isSelected: isSelected)
            }
            .padding(.horizontal, Space.xl)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                Capsule(style: .continuous)
                    .fill(Palette.coral.opacity(isSelected ? 0.10 : 0))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Palette.coral.opacity(isSelected ? 1 : 0), lineWidth: 1.5)
                    }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(OptionPressStyle())
        .glassSurface(cornerRadius: 999, interactive: true)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OptionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Glass rows (settings surfaces)

/// One row inside a glass group: a bare glyph, a short title, and an
/// optional quiet trailing value and chevron. Rows name things; they don't
/// explain them.
struct GlassRow: View {
    let icon: String
    var iconColor: Color = Palette.dim
    let title: String
    var titleColor: Color = Palette.ink
    var value: String?
    var showsChevron = false

    var body: some View {
        HStack(spacing: Space.md) {
            GlassRowIcon(icon: icon, color: iconColor)
            Text(title)
                .font(Typeface.body(16))
                .foregroundStyle(titleColor)
                .lineLimit(1)
            Spacer(minLength: Space.md)
            if let value {
                Text(value)
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.faint)
            }
        }
        .padding(.vertical, Space.md)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// A row's glyph, bare: no tinted square behind it, which read as
/// templated. Quiet ink by default, so coral stays the screen's accent;
/// callers colour it only when the colour means something.
struct GlassRowIcon: View {
    /// Its slot, so titles line up down a list and retries can indent to it.
    static let width: CGFloat = 24

    let icon: String
    var color: Color = Palette.dim

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(color)
            .frame(width: Self.width, height: 24)
    }
}

struct GlassRowDivider: View {
    var body: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }
}

/// A grouped glass container for a cluster of `GlassRow`s. Never nested.
struct GlassRowGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, Space.lg)
            .glassSurface(cornerRadius: Corner.lg)
    }
}

// MARK: - Back chevron and progress

/// Round glass chevron for onboarding, auth and sub-page headers — 44pt, a
/// quiet wayfinding control but never toy-sized.
struct GlassBackButton: View {
    let action: () -> Void

    var body: some View {
        GlassIconButton(systemImage: "chevron.left", size: 44, iconSize: 16, color: Palette.ink, accessibilityLabel: String(localized: "Back", bundle: AppLanguage.bundle), action: action)
    }
}

/// A 3pt gradient capsule — the questionnaire's progress.
struct ProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.09))
                Capsule()
                    .fill(LinearGradient(colors: [Palette.peach, Palette.coral], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, proxy.size.width * fraction))
                    .animation(.easeInOut(duration: 0.32), value: fraction)
            }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

// MARK: - Status bar scrim

/// Keeps scrolling content from running through the clock and signal
/// icons: a slice of the stage's own paper (sky and grain, aligned to the
/// real stage) over the status bar only, softening out across its lower
/// edge. Nothing below the status bar is touched — a taller fade ate into
/// the page. (The iOS 26 scroll edge effect needs a real top bar; these
/// screens hide theirs.) Never takes touches.
struct StatusBarScrim: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                let inset = proxy.safeAreaInsets.top
                MorningPaper()
                    .mask(alignment: .top) {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.7),
                                .init(color: .black.opacity(0), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: inset)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea()
                    }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func statusBarScrim() -> some View { modifier(StatusBarScrim()) }
}

// MARK: - Scroll edge fade

extension View {
    /// Fades the *content* out over its bottom edge, rather than painting a
    /// colour over it. A painted fade has to guess the colour behind it, and
    /// over the stage's sunrise it guesses wrong — a lighter band with a hard
    /// edge. A mask dissolves into whatever is really there.
    func bottomEdgeFade(_ height: CGFloat = 36) -> some View {
        mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
            }
        }
    }
}

// MARK: - Swipe back

/// The system's edge swipe back on every NavigationStack page. Our pages
/// hide the navigation bar for their own glass chevron, and hiding it
/// switches the pop gesture off; this turns it back on, so a page follows
/// the finger as it does in any app. Only when there's somewhere to go back
/// to: on a stack's root the gesture would freeze the screen.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        // iOS 26's back swipe from anywhere on the page, not just the edge.
        if #available(iOS 26.0, *) {
            interactiveContentPopGestureRecognizer?.delegate = self
        }
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

/// Left-edge swipe → back, mirroring the glass chevron, for flows that are
/// custom transitions rather than a NavigationStack (onboarding, sign-in),
/// where the system pop gesture doesn't exist. A trigger, not a tracked pop. Call sites tap `soft()` —
/// a swipe is a non-button cue, never the button knock.
extension View {
    func swipeBack(_ action: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard value.startLocation.x <= 44,
                              value.translation.width > 70,
                              abs(value.translation.height) < abs(value.translation.width)
                        else { return }
                        action()
                    }
            )
    }
}

// MARK: - Keyboard warmup

/// The first keyboard in a process pays a cold path that hitches whatever
/// animation it lands in. `warmFrameworks()` loads the input frameworks while
/// the welcome screen idles — become + resign in one runloop turn, so nothing
/// appears. Never hold the warmup field as first responder across frames: the
/// flow opens on the language step, and a held field shows a real keyboard
/// over it.
@MainActor
enum Keyboard {
    private static var didWarmFrameworks = false

    private static var activeWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
    }

    private static func makeWarmupField(in window: UIWindow) -> UITextField {
        let field = UITextField(frame: CGRect(x: -1, y: -1, width: 1, height: 1))
        field.alpha = 0.01
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        field.isAccessibilityElement = false
        window.addSubview(field)
        return field
    }

    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    static func warmFrameworks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !didWarmFrameworks, let window = activeWindow else { return }
            didWarmFrameworks = true
            let field = makeWarmupField(in: window)
            field.becomeFirstResponder()
            field.resignFirstResponder()
            field.removeFromSuperview()
        }
    }
}

// MARK: - Slider

/// The flow's grammar for "how much": a live hero number that rolls, a
/// gradient-filled rail, end labels, and one haptic tick per step.
/// Hand-built rather than SwiftUI's `Slider` — the fill, the numeric roll and
/// the per-step tick are unreachable through the stock control, and the tick
/// is most of what makes an answer feel chosen rather than dragged.
struct CoachSlider: View {
    @Binding var value: Int
    /// Whether the user has actually moved it — a plausible default must not
    /// be accepted as an answer.
    @Binding var touched: Bool
    let range: ClosedRange<Int>
    var lowLabel: String
    var highLabel: String
    var caption: String?
    var unit: String?
    var accessibilityName: String

    private let knob: CGFloat = 28
    private let trackHeight: CGFloat = 5

    private var fraction: Double {
        let span = Double(range.upperBound - range.lowerBound)
        return span > 0 ? Double(value - range.lowerBound) / span : 0
    }

    var body: some View {
        VStack(spacing: Space.huge) {
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(Typeface.hero(56))
                    .foregroundStyle(touched ? Palette.ink : Palette.muted)
                    .contentTransition(.numericText(value: Double(value)))
                    .animation(.snappy(duration: 0.18), value: value)
                if let unit {
                    Text(unit)
                        .font(Typeface.body(15))
                        .foregroundStyle(Palette.dim)
                }
            }

            VStack(spacing: Space.md) {
                track
                HStack {
                    Text(lowLabel)
                    Spacer()
                    Text(highLabel)
                }
                .font(Typeface.body(13))
                .foregroundStyle(Palette.muted)
            }

            if let caption {
                Text(caption)
                    .font(Typeface.bodyItalic(14))
                    .foregroundStyle(Palette.muted)
            }
        }
        // To VoiceOver (and UI tests) this *is* a slider: the system control
        // stands in for the custom drawing, with the same binding.
        .accessibilityRepresentation {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { newValue in
                        touched = true
                        set(Int(newValue.rounded()))
                    }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            ) {
                Text(accessibilityName)
            }
            .accessibilityValue("\(value) \(unit ?? "")")
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - knob)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.ink.opacity(0.10))
                    .frame(height: trackHeight)
                    .padding(.horizontal, knob / 2)
                Capsule()
                    .fill(LinearGradient(colors: [Palette.peach, Palette.coral], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(trackHeight, travel * fraction + knob / 2), height: trackHeight)
                    .padding(.leading, knob / 2)
                    .opacity(touched ? 1 : 0.5)
                Circle()
                    .fill(Palette.ink)
                    .frame(width: knob, height: knob)
                    .shadow(color: Palette.ink.opacity(0.25), radius: 6, y: 2)
                    .offset(x: travel * fraction)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        touched = true
                        let x = min(max(0, drag.location.x - knob / 2), travel)
                        let span = Double(range.upperBound - range.lowerBound)
                        set(range.lowerBound + Int((x / travel * span).rounded()))
                    }
            )
        }
        .frame(height: 44)
    }

    /// Ticks only when the value genuinely moves, so a slow drag across one
    /// step doesn't machine-gun the haptics.
    private func set(_ raw: Int) {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        guard clamped != value else { return }
        value = clamped
        Haptics.soft()
    }
}
