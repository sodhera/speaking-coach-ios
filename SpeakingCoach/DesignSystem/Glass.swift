import SwiftUI

// MARK: - Liquid Glass
//
// Native `glassEffect` on iOS 26+, a white-washed `.ultraThinMaterial` with a
// hairline on earlier systems. Call sites never check availability themselves.
//
// Rules (same as the sibling app, learned the hard way):
// - The glass owns its chrome. Never paint a fill or border over a glass
//   surface; on 26 that flattens the real material into a tinted panel.
//   Strokes are added only when they carry meaning (a selection ring).
// - Buttons react through a custom `ButtonStyle` that owns `isPressed`. A
//   plain button over `.interactive()` glass swallows the touch and feels dead.
// - A custom style must read `isEnabled` itself, or a disabled button stays
//   bright while silently ignoring taps.

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?
    var strength: Double
    var interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(glass.tint(Color.white.opacity(strength)), in: shape)
        } else {
            content
                .background((tint ?? .clear).opacity(strength), in: shape)
                .background(Palette.glassFill.opacity(strength), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        return interactive ? glass.interactive() : glass
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = Corner.lg, tint: Color? = nil, strength: Double = 1, interactive: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint, strength: strength, interactive: interactive))
    }
}

/// Groups sibling glass shapes so iOS 26 renders them as one set (they sample
/// and blend together). A passthrough before 26. Wrap exactly one layout view.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Buttons

/// The one primary action on a screen: coral glass, white label, soft glow.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading = false
    /// Draws the symbol after the title — for directional arrows.
    var trailingIcon = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            ZStack {
                HStack(spacing: Space.sm) {
                    if let systemImage, !trailingIcon { Image(systemName: systemImage) }
                    Text(title).font(Typeface.label(17)).tracking(0.1)
                    if let systemImage, trailingIcon { Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)) }
                }
                .opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(.white) }
            }
            .foregroundStyle(isEnabled ? Color.white : Palette.muted)
        }
        .buttonStyle(CapsuleActionStyle(prominent: true))
        .shadow(color: Palette.coral.opacity(isEnabled ? 0.32 : 0), radius: 18, y: 8)
        .allowsHitTesting(!isLoading)
    }
}

/// A quieter full-width action: untinted glass, ink label.
struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            Label {
                Text(title).font(Typeface.label(17))
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .foregroundStyle(Palette.ink)
        }
        .buttonStyle(CapsuleActionStyle(prominent: false))
    }
}

/// A chromeless text action ("I already have an account").
struct QuietButton: View {
    let title: String
    var color: Color = Palette.dim
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            Text(title)
                .font(Typeface.body(15))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Full-width capsule chrome with a guaranteed springy press.
struct CapsuleActionStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, Space.lg)
            .contentShape(Capsule())
            // Not yet tappable, the primary goes neutral rather than faded
            // coral: a washed-out pink read as broken, not as "not yet".
            .modifier(CapsuleChrome(prominent: prominent && isEnabled))
            .scaleEffect(pressed ? 0.965 : 1)
            .opacity(isEnabled || prominent ? 1 : 0.45)
            .animation(Motion.press, value: pressed)
            .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

private struct CapsuleChrome: ViewModifier {
    var prominent: Bool

    func body(content: Content) -> some View {
        let shape = Capsule(style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(prominent ? .regular.tint(Palette.coral).interactive() : .regular.interactive(), in: shape)
        } else if prominent {
            content.background {
                shape.fill(LinearGradient(colors: [Palette.coral, Color(hex: 0xF4474F)], startPoint: .top, endPoint: .bottom))
                    .overlay { shape.strokeBorder(.white.opacity(0.22), lineWidth: 1) }
            }
        } else {
            content.glassSurface(cornerRadius: 999, interactive: true)
        }
    }
}

/// A small circular icon action — back chevron, close, settings.
struct GlassIconButton: View {
    let systemImage: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 17
    var color: Color = Palette.ink
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(CircleGlassStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct CircleGlassStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(CircleChrome())
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.45), value: configuration.isPressed)
    }
}

private struct CircleChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(Palette.glassFill, in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(Palette.border, lineWidth: 1) }
        }
    }
}
