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
            try await Task.sleep(for: .milliseconds(420))
            for index in lines.indices {
                try Task.checkCancellation()
                if index > 0 {
                    withAnimation(Self.stepBack) { current = index }
                    shown = 0
                    try await Task.sleep(for: .milliseconds(180))
                }
                let characters = Array(lines[index])
                var sinceTick = 0
                for character in 1...max(1, characters.count) {
                    try Task.checkCancellation()
                    if skipCurrentLine {
                        shown = characters.count
                        break
                    }
                    shown = character
                    sinceTick += 1
                    let isBoundary = character < characters.count && characters[character - 1] == " "
                    if isBoundary, sinceTick >= 4 {
                        sinceTick = 0
                        Haptics.tick(0.34)
                    }
                    try await Task.sleep(for: .milliseconds(38))
                }
                skipCurrentLine = false
                Haptics.rigid()
                try await Task.sleep(for: .milliseconds(380))
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
