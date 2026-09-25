import SwiftUI
import UIKit

/// Sentences arrive one at a time and the ones before them fall back.
///
/// The line being typed is full size in `ink`; every line already said
/// shrinks to 0.9, dims and steps back, so the stack reads as a conversation
/// with the newest thing at the front. A tap anywhere finishes the line being
/// typed — deliberately unlabelled; a "tap to speed up" hint undercuts the
/// writing. Haptics tick on word boundaries (with a four-character floor, so
/// short words don't machine-gun) and each sentence lands on a firmer
/// `rigid`. Reduce Motion and VoiceOver get the complete text at once.
struct NarrativePage: View {
    let lines: [String]
    @Binding var ready: Bool
    var fontSize: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var current = 0
    @State private var shown = 0
    @State private var skipCurrentLine = false

    /// `.smooth`, not a spring: three lines overshooting by three different
    /// distances at once reads as wobble. Nothing here is thrown.
    private static let stepBack = Animation.smooth(duration: 0.5)

    private var size: CGFloat { fontSize ?? (lines.count == 1 ? 28 : 24) }

    var body: some View {
        VStack(spacing: 20) {
            ForEach(lines.indices.filter { $0 <= current }, id: \.self) { index in
                let isCurrent = index == current
                RevealingSentence(
                    line: lines[index],
                    shown: isCurrent ? shown : lines[index].count,
                    color: UIColor(Palette.ink),
                    fontSize: size
                )
                .frame(maxWidth: .infinity)
                // Retirement is a SwiftUI colour multiply, not a new label
                // colour — setting `textColor` from `updateUIView` lands
                // outside the animation and snaps on one frame.
                .colorMultiply(isCurrent ? .white : Palette.muted)
                .scaleEffect(isCurrent ? 1 : 0.9, anchor: .center)
                .opacity(isCurrent ? 1 : 0.75)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity))
            }
        }
        .animation(Self.stepBack, value: current)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.joined(separator: " "))
        .task(id: lines) { await play() }
    }

    private func play() async {
        current = 0
        shown = 0
        skipCurrentLine = false
        ready = false
        if reduceMotion || voiceOver {
            finish()
            return
        }
        do {
            // A cold feedback generator fires weakly or not at all — warm it
            // before the first word.
            Haptics.prepare()
            try await Task.sleep(for: Typewriter.lead)
            for index in lines.indices {
                try Task.checkCancellation()
                if index > 0 {
                    withAnimation(Self.stepBack) { current = index }
                    shown = 0
                    try await Task.sleep(for: .milliseconds(180))
                }
                try await Typewriter.type(lines[index], skipped: { skipCurrentLine }, show: { shown = $0 })
                skipCurrentLine = false
                try await Task.sleep(for: Typewriter.settle)
            }
            finish()
        } catch { /* Navigation cancels the reveal. */ }
    }

    private func skip() {
        guard !ready, current < lines.count, shown < lines[current].count else { return }
        skipCurrentLine = true
        Haptics.soft()
    }

    private func finish() {
        withAnimation(Self.stepBack) { current = max(0, lines.count - 1) }
        shown = lines.last?.count ?? 0
        ready = true
    }
}

/// The typing rhythm every revealed sentence shares: a character every
/// 38ms, a soft tick on word boundaries (with a four-character floor, so
/// short words don't machine-gun), and a firmer `rigid` as the sentence
/// lands. The `.soft` feel keeps the same beats but lands them on the soft
/// generator, for moments that should feel set down rather than struck.
enum Typewriter {
    static let lead: Duration = .milliseconds(420)
    static let settle: Duration = .milliseconds(380)
    static let interval: Duration = .milliseconds(38)

    enum Feel { case firm, soft }

    @MainActor
    static func type(_ line: String, interval: Duration = interval, feel: Feel = .firm, skipped: () -> Bool, show: (Int) -> Void) async throws {
        let characters = Array(line)
        var sinceTick = 0
        for character in 1...max(1, characters.count) {
            try Task.checkCancellation()
            if skipped() {
                show(characters.count)
                break
            }
            show(character)
            sinceTick += 1
            let isBoundary = character < characters.count && characters[character - 1] == " "
            if isBoundary, sinceTick >= 4 {
                sinceTick = 0
                if feel == .soft { Haptics.soft(0.55) } else { Haptics.tick(0.34) }
            }
            try await Task.sleep(for: interval)
        }
        if feel == .soft { Haptics.soft(0.9) } else { Haptics.rigid() }
    }
}

/// Sentences typed one after another in place, each already laid out at
/// its final size so nothing below them moves while they type. A tap
/// finishes the sentence being typed. Reduce Motion and VoiceOver get the
/// whole text at once.
struct TypedParagraphs: View {
    struct Line: Hashable {
        let text: String
        let size: CGFloat
        var weight: CGFloat = 500
        var color: Color = Palette.ink
    }

    let lines: [Line]
    var spacing: CGFloat = Space.xl
    /// Wait before the first word, so it follows whatever arrived above it.
    var delay: Duration = Typewriter.lead
    var interval: Duration = Typewriter.interval
    var feel: Typewriter.Feel = .firm
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var current = 0
    @State private var shown = 0
    @State private var skipCurrent = false
    @State private var done = false

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(lines.indices, id: \.self) { index in
                let line = lines[index]
                RevealingSentence(
                    line: line.text,
                    shown: done || index < current ? line.text.count : index == current ? shown : 0,
                    color: UIColor(line.color),
                    fontSize: line.size,
                    weight: line.weight
                )
                .frame(maxWidth: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !done, !skipCurrent else { return }
            skipCurrent = true
            Haptics.soft()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.map(\.text).joined(separator: " "))
        .task(id: lines) { await play() }
    }

    private func play() async {
        current = 0
        shown = 0
        done = false
        if reduceMotion || voiceOver { finish(); return }
        do {
            Haptics.prepare()
            try await Task.sleep(for: delay)
            for index in lines.indices {
                current = index
                shown = 0
                skipCurrent = false
                try await Typewriter.type(lines[index].text, interval: interval, feel: feel, skipped: { skipCurrent }, show: { shown = $0 })
                try await Task.sleep(for: Typewriter.settle)
            }
            finish()
        } catch { /* Navigation cancels the reveal. */ }
    }

    private func finish() {
        done = true
        onFinished()
    }
}

/// A `UILabel` measures the *complete* sentence before painting the visible
/// prefix, which keeps word wrapping fixed while the typewriter reveals each
/// character — words never jump lines mid-reveal.
struct RevealingSentence: UIViewRepresentable {
    let line: String
    let shown: Int
    let color: UIColor
    let fontSize: CGFloat
    var weight: CGFloat = 500

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        configure(label)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) { configure(label) }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        label.preferredMaxLayoutWidth = width
        let height = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: height)
    }

    private func configure(_ label: UILabel) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let text = NSMutableAttributedString(string: line, attributes: [
            .font: Typeface.uiFont(size: fontSize, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
        let prefixLength = String(line.prefix(shown)).utf16.count
        let remaining = (line as NSString).length - prefixLength
        if remaining > 0 {
            text.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: prefixLength, length: remaining))
        }
        label.attributedText = text
    }
}

/// A single line that inks itself in: each letter arrives in the typewriter's
/// order, but rises out of a soft blur over a few letters' time instead of
/// snapping on — written rather than printed. A soft tap on each word
/// boundary and a fuller one as the line lands; a tap on it finishes the line.
/// Reduce Motion and VoiceOver get the whole line at once.
///
/// The per-letter blur needs iOS 18's `TextRenderer`; iOS 17 gets the same
/// timing as a fade alone.
struct InkedLine: View {
    let text: String
    let font: Font
    var color: Color = Palette.ink
    var plays = true
    var delay: Duration = Typewriter.lead
    var interval: Duration = .milliseconds(65)
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var start: Date?
    @State private var done = false
    @State private var skipped = false

    /// How many letters' time each letter takes to fully ink in.
    private static let span: Double = 3.5

    var body: some View {
        TimelineView(.animation(paused: done || start == nil)) { timeline in
            label(progress: progress(at: timeline.date))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard start != nil, !done, !skipped else { return }
            skipped = true
            Haptics.soft()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .task { await play() }
    }

    private var total: Double { Double(text.count) + Self.span }
    private var seconds: Double { Double(interval.components.attoseconds) / 1e18 + Double(interval.components.seconds) }

    private func progress(at date: Date) -> Double {
        if done || skipped || !plays { return total }
        guard let start else { return 0 }
        return date.timeIntervalSince(start) / seconds
    }

    @ViewBuilder
    private func label(progress: Double) -> some View {
        if #available(iOS 18.0, *) {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .textRenderer(InkRenderer(progress: progress, span: Self.span))
        } else {
            Text(fadedText(progress: progress))
                .font(font)
        }
    }

    private func fadedText(progress: Double) -> AttributedString {
        var result = AttributedString()
        for (index, character) in text.enumerated() {
            var run = AttributedString(String(character))
            run.foregroundColor = color.opacity(Self.ink(progress: progress, index: index, span: Self.span))
            result += run
        }
        return result
    }

    /// How inked the letter at `index` is, 0 → 1, smoothstepped.
    static func ink(progress: Double, index: Int, span: Double) -> Double {
        let raw = min(max((progress - Double(index)) / span, 0), 1)
        return raw * raw * (3 - 2 * raw)
    }

    private func play() async {
        guard plays, !reduceMotion, !voiceOver else {
            done = true
            onFinished()
            return
        }
        do {
            Haptics.prepare()
            try await Task.sleep(for: delay)
            start = .now
            let characters = Array(text)
            var sinceTick = 0
            for index in characters.indices {
                if skipped { break }
                sinceTick += 1
                if characters[index] == " ", sinceTick >= 4 {
                    sinceTick = 0
                    Haptics.soft(0.55)
                }
                try await Task.sleep(for: interval)
            }
            Haptics.soft(0.9)
            if !skipped { try await Task.sleep(for: interval * Int(Self.span.rounded(.down))) }
            done = true
            try await Task.sleep(for: Typewriter.settle)
            onFinished()
        } catch { /* Navigation cancels the reveal. */ }
    }
}

/// Draws each glyph at its own point in the ink: faint, blurred and a few
/// points low as it starts, sharp and in place once it's done.
@available(iOS 18.0, *)
private struct InkRenderer: TextRenderer {
    let progress: Double
    let span: Double

    var displayPadding: EdgeInsets { EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12) }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var index = 0
        for line in layout {
            for run in line {
                for glyph in run {
                    let amount = InkedLine.ink(progress: progress, index: index, span: span)
                    index += 1
                    if amount <= 0 { continue }
                    if amount >= 1 {
                        context.draw(glyph)
                        continue
                    }
                    var letter = context
                    letter.opacity = amount
                    letter.translateBy(x: 0, y: (1 - amount) * 5)
                    letter.addFilter(.blur(radius: (1 - amount) * 7))
                    letter.draw(glyph)
                }
            }
        }
    }
}
