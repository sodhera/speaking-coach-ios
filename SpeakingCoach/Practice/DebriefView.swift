import SwiftUI

/// The payoff, as two views of the same rehearsal.
///
/// **Feedback** reads as one argument, top to bottom: the read in a sentence,
/// then the session's criteria at a glance (so a summary that mentions
/// "situation, action and result" points at something on screen), one thing
/// to keep, and one thing to change with the exact moment to go back to.
///
/// **Conversation** is the whole transcript as a chat. The lines the feedback
/// talks about are marked where they happened, and tapping a quote in
/// Feedback jumps there.
///
/// Honest by construction: every quote is a line the user actually said
/// (the server rejects any assessment that cites words not in the
/// transcript), a retry's comparison is one criterion on one rubric and says
/// so, and nothing here rates accent, confidence or personality.
struct DebriefView: View {
    enum Tab: Hashable { case feedback, conversation }

    let report: PracticeReport
    let definition: PracticeDefinition
    /// False when this rehearsal's one retry has already been used.
    var retryAvailable = true
    var onRetry: (() -> Void)?
    var onRehearseAgain: (() -> Void)?
    let onDone: () -> Void

    @State private var tab: Tab = .feedback
    @State private var openCriteria: Set<String> = []
    /// The line a tapped quote asked to see, outlined for a moment.
    @State private var spotlight: String?

    private var assessment: PracticeAssessment? { report.analysis.practice }
    private var comparison: RetryComparison? { RetryComparison(report: report) }
    private var checkpoint: RetryCheckpoint? { retryAvailable ? RetryCheckpoint.make(from: report) : nil }
    private var hasConversation: Bool { !report.transcript.isEmpty }

    private var strength: CriterionResult? {
        assessment?.criteria.filter { $0.level > 0 }.max { $0.level < $1.level }
    }

    /// The criterion "Try one change" is about.
    private var focus: CriterionResult? {
        assessment.flatMap { assessment in assessment.criteria.first { $0.id == assessment.targetCriterionId } }
    }

    /// The partner's question a retry returns to, when a retry is offered.
    private var momentLineID: String? {
        guard checkpoint != nil, onRetry != nil, let focus,
              let index = RetryCheckpoint.questionIndex(for: focus, in: report.transcript)
        else { return nil }
        return report.transcript[index].id
    }

    private var title: String {
        let base = report.analysis.custom?.title ?? definition.title
        return comparison == nil ? base : String(localized: "Retry · \(definition.title)", bundle: AppLanguage.bundle)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            // Both views stay mounted, so switching keeps each one's scroll
            // position and the feedback's reveal plays once.
            ZStack {
                feedback
                    .opacity(tab == .feedback ? 1 : 0)
                    .allowsHitTesting(tab == .feedback)
                    .accessibilityHidden(tab != .feedback)
                if hasConversation {
                    conversation
                        .opacity(tab == .conversation ? 1 : 0)
                        .allowsHitTesting(tab == .conversation)
                        .accessibilityHidden(tab != .conversation)
                }
            }
            // Content dissolves under the header and into the stage above
            // the actions.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: Space.xxl)
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 36)
                }
            }

            actions
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.sm)
                .padding(.bottom, Space.sm)
        }
    }

    private var header: some View {
        HStack(spacing: Space.md) {
            if hasConversation { DebriefTabs(selection: $tab) }
            Spacer(minLength: 0)
            GlassIconButton(systemImage: "xmark", size: 44, iconSize: 14, color: Palette.dim, accessibilityLabel: String(localized: "Close", bundle: AppLanguage.bundle), action: onDone)
        }
        .padding(.horizontal, Space.xxl)
        .padding(.top, Space.sm)
    }

    // MARK: Feedback

    private var feedback: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.md) {
                    titleLabel
                    verdict.revealIn(after: 0.1)
                }

                if let comparison {
                    whatChanged(comparison).revealIn(after: 0.3)
                }

                if comparison == nil, let assessment, !assessment.criteria.isEmpty {
                    scorecard(assessment).revealIn(after: 0.3)
                }

                if assessment == nil { legacyFeedback }

                if let strength {
                    card(title: String(localized: "Keep this", bundle: AppLanguage.bundle)) {
                        Text(strength.note)
                            .font(Typeface.body(16))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let evidence = strength.evidence.first { quote(evidence) }
                    }
                    .revealIn(after: 0.5)
                }

                if let adjustment = assessment?.adjustment {
                    card(title: String(localized: "Try one change", bundle: AppLanguage.bundle), surface: Palette.coral.opacity(0.07)) {
                        Text(adjustment)
                            .font(Typeface.body(17))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let checkpoint, onRetry != nil {
                            VStack(alignment: .leading, spacing: Space.sm) {
                                MarkLabel(text: String(localized: "The moment to retry", bundle: AppLanguage.bundle), systemImage: "arrow.counterclockwise", color: Palette.coralDeep)
                                bubbleButton(lineID: momentLineID) {
                                    SpeechBubble(text: AttributedString(checkpoint.prompt), speaker: .partner, size: 15)
                                }
                                .padding(.trailing, Space.xxl)
                            }
                            .padding(.top, Space.xs)
                        }
                    }
                    .revealIn(after: 0.7)
                }

                if assessment != nil {
                    card(title: String(localized: "Take it into real life", bundle: AppLanguage.bundle)) {
                        Text(definition.transfer)
                            .font(Typeface.body(16))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(definition.scaffold)
                            .font(Typeface.bodyItalic(15))
                            .foregroundStyle(Palette.dim)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .revealIn(after: 0.9)
                }

                Text("Based on the words captured in this session, not a rating of your accent or personality.")
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xxl)
            .padding(.bottom, Space.xxxl)
        }
    }

    /// Which session this is, quietly — the verdict under it is the headline.
    private var titleLabel: some View {
        Text(title)
            .font(Typeface.label(14))
            .foregroundStyle(Palette.muted)
    }

    private var verdict: some View {
        Text(assessment?.summary ?? report.analysis.summary ?? String(localized: "Your session is saved.", bundle: AppLanguage.bundle))
            .font(Typeface.title(20))
            .foregroundStyle(Palette.ink)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: What we listened for

    /// Every criterion on one card: a mark and a level word you can read at a
    /// glance, with the note and quote a tap away. The two criteria the cards
    /// below talk about are named, so the cards read as part of this.
    private func scorecard(_ assessment: PracticeAssessment) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionTitle(text: String(localized: "How you did", bundle: AppLanguage.bundle))
            VStack(spacing: 0) {
                ForEach(Array(assessment.criteria.enumerated()), id: \.element.id) { index, criterion in
                    if index > 0 { GlassRowDivider() }
                    criterionRow(criterion)
                }
            }
            .padding(.horizontal, Space.lg)
            .glassSurface(cornerRadius: Corner.lg)
        }
    }

    private func criterionRow(_ criterion: CriterionResult) -> some View {
        let isOpen = openCriteria.contains(criterion.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(.easeInOut(duration: 0.28)) { openCriteria.formSymmetricDifference([criterion.id]) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    Text(criterionLabel(criterion.id))
                        .font(Typeface.label(16))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.sm)
                    LevelPill(level: criterion.level)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.vertical, Space.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? String(localized: "Hides why", bundle: AppLanguage.bundle) : String(localized: "Shows why", bundle: AppLanguage.bundle))

            if isOpen {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text(criterion.note)
                        .font(Typeface.body(15))
                        .foregroundStyle(Palette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(criterion.evidence, id: \.turnId) { quote($0) }
                }
                .padding(.bottom, Space.lg)
                .transition(.opacity)
            }
        }
    }

    private func criterionLabel(_ id: String) -> String {
        definition.criteria.first { $0.id == id }?.name ?? String(localized: "Criterion", bundle: AppLanguage.bundle)
    }

    // MARK: Older reports

    /// Custom situations and reports from before the practice rubric carry
    /// scores, tips and rewrites instead of criteria.
    @ViewBuilder
    private var legacyFeedback: some View {
        if let subscores = report.analysis.subscores, !subscores.isEmpty {
            card(title: String(localized: "How it went", bundle: AppLanguage.bundle)) {
                ForEach(subscores, id: \.label) { subscore in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack {
                            Text(subscore.label).font(Typeface.label(15)).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(Self.band(subscore.score)).font(Typeface.body(13)).foregroundStyle(Palette.dim)
                        }
                        ScoreBar(value: Double(subscore.score) / 100)
                        Text(subscore.note)
                            .font(Typeface.body(14))
                            .foregroundStyle(Palette.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .revealIn(after: 0.35)
        }

        if let improvements = report.analysis.improvements, !improvements.isEmpty {
            card(title: report.analysis.custom == nil ? String(localized: "What to work on", bundle: AppLanguage.bundle) : String(localized: "Try these", bundle: AppLanguage.bundle)) {
                ForEach(Array(improvements.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: Space.sm) {
                        Text("\(index + 1)")
                            .font(Typeface.label(12))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Palette.coral))
                        Text(item).font(Typeface.body(16)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .revealIn(after: 0.6)
        }

        if let rewrites = report.analysis.rewrites, !rewrites.isEmpty {
            card(title: String(localized: "Say it better", bundle: AppLanguage.bundle)) {
                ForEach(rewrites, id: \.original) { rewrite in
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("You said").font(Typeface.label(12)).foregroundStyle(Palette.muted)
                        SpeechBubble(text: AttributedString(rewrite.original), speaker: .user, size: 15)
                            .opacity(0.8)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.leading, Space.xxl)
                        Text("Try").font(Typeface.label(12)).foregroundStyle(Palette.sage).padding(.top, Space.xs)
                        Text(rewrite.better)
                            .font(Typeface.body(16))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            .revealIn(after: 0.85)
        }
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.md) {
                    titleLabel
                        .padding(.bottom, Space.sm)
                    ForEach(Array(report.transcript.enumerated()), id: \.element.id) { index, line in
                        conversationLine(line, showsName: !report.transcript[..<index].contains { $0.role == line.role })
                            .id(line.id)
                    }
                    Text("Transcribed from your session, so the odd word may be off.")
                        .font(Typeface.body(12))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, Space.lg)
                }
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xxl)
                .padding(.bottom, Space.xxxl)
            }
            .onChange(of: spotlight) { _, lineID in
                guard let lineID else { return }
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(lineID, anchor: .center) }
            }
        }
    }

    private func conversationLine(_ line: TranscriptLine, showsName: Bool) -> some View {
        let isUser = line.role == .user
        let marks = marks(for: line)
        return VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if showsName {
                Text(isUser ? String(localized: "You", bundle: AppLanguage.bundle) : definition.partner)
                    .font(Typeface.label(12))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, Space.xs)
            }
            SpeechBubble(
                text: highlighted(line, marks: marks),
                speaker: isUser ? .user : .partner,
                isSpotlit: spotlight == line.id
            )
            .textSelection(.enabled)
            ForEach(marks, id: \.self) { mark in
                MarkLabel(text: mark.title, systemImage: mark.systemImage, color: mark.color)
                    .padding(.horizontal, Space.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(isUser ? .leading : .trailing, Space.huge)
        .padding(.top, marks.isEmpty ? 0 : Space.xs)
        .padding(.bottom, marks.isEmpty ? 0 : Space.sm)
    }

    private enum LineMark: Hashable {
        case keep, focus, moment

        var title: String {
            switch self {
            case .keep: String(localized: "Keep this", bundle: AppLanguage.bundle)
            case .focus: String(localized: "Your focus", bundle: AppLanguage.bundle)
            case .moment: String(localized: "The moment to retry", bundle: AppLanguage.bundle)
            }
        }

        var systemImage: String {
            switch self {
            case .keep: "hand.thumbsup.fill"
            case .focus: "arrow.turn.up.right"
            case .moment: "arrow.counterclockwise"
            }
        }

        var color: Color { self == .keep ? Palette.sage : Palette.coralDeep }
    }

    /// Only the lines the feedback cards quote are marked, so the chat reads
    /// as the same story and not as a second, denser report.
    private func marks(for line: TranscriptLine) -> [LineMark] {
        var marks: [LineMark] = []
        if line.id == momentLineID { marks.append(.moment) }
        if let strength, strength.id != focus?.id, strength.evidence.first?.turnId == line.id { marks.append(.keep) }
        if let focus, focus.evidence.first?.turnId == line.id { marks.append(.focus) }
        return marks
    }

    /// The quoted words stay in ink and the rest of the line steps back, so a
    /// marked line shows exactly which words the feedback meant. A tint read
    /// as mud on the coral bubble.
    private func highlighted(_ line: TranscriptLine, marks: [LineMark]) -> AttributedString {
        var text = AttributedString(line.text)
        let quotes: [(CriterionResult?, LineMark)] = [(strength, .keep), (focus, .focus)]
        let ranges = quotes.compactMap { criterion, mark -> Range<AttributedString.Index>? in
            guard marks.contains(mark), let quote = criterion?.evidence.first?.quote else { return nil }
            return text.range(of: quote, options: [.caseInsensitive, .diacriticInsensitive])
        }
        guard !ranges.isEmpty else { return text }
        text.foregroundColor = Palette.dim
        for range in ranges { text[range].foregroundColor = Palette.ink }
        return text
    }

    /// Shows a line in the conversation, outlined for a moment.
    private func show(_ lineID: String) {
        withAnimation(.easeInOut(duration: 0.3)) { tab = .conversation }
        spotlight = lineID
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeOut(duration: 0.6)) {
                if spotlight == lineID { spotlight = nil }
            }
        }
    }

    // MARK: Actions

    /// One action at most, and never "Done": the ✕ already closes. The retry
    /// leads when there's a moment to go back to — the fastest way from "try
    /// one change" to having actually tried it.
    @ViewBuilder
    private var actions: some View {
        if checkpoint != nil, let onRetry {
            PrimaryButton(title: String(localized: "Retry this moment · 90 sec", bundle: AppLanguage.bundle), systemImage: "arrow.counterclockwise", action: onRetry)
        } else if comparison != nil || report.analysis.custom != nil, let onRehearseAgain {
            PrimaryButton(
                title: report.analysis.custom == nil ? String(localized: "Practice the whole scene again", bundle: AppLanguage.bundle) : String(localized: "Practice it again", bundle: AppLanguage.bundle),
                systemImage: "mic.fill",
                action: onRehearseAgain
            )
        }
    }

    // MARK: What changed

    private func whatChanged(_ comparison: RetryComparison) -> some View {
        let headline = comparison.change > 0
            ? String(localized: "Clearer this time.", bundle: AppLanguage.bundle)
            : comparison.change == 0 ? String(localized: "The same level, so far.", bundle: AppLanguage.bundle) : String(localized: "This one needs another go.", bundle: AppLanguage.bundle)
        return VStack(alignment: .leading, spacing: Space.md) {
            SectionTitle(text: String(localized: "What changed", bundle: AppLanguage.bundle))
            VStack(alignment: .leading, spacing: Space.lg) {
                Text(headline)
                    .font(Typeface.title(22))
                    .foregroundStyle(comparison.change > 0 ? Palette.sage : Palette.ink)
                Text(definition.criteria.contains { $0.id == comparison.after.id } ? criterionLabel(comparison.after.id) : String(localized: "The moment you retried", bundle: AppLanguage.bundle))
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
                beforeAfterRow(String(localized: "Before", bundle: AppLanguage.bundle), comparison.before, faded: true)
                beforeAfterRow(String(localized: "Now", bundle: AppLanguage.bundle), comparison.after, faded: false)
                Text("One session compared with one retry. A direction, not proof of lasting change.")
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: Corner.lg, tint: comparison.change > 0 ? Palette.sage.opacity(0.08) : nil)
        }
    }

    private func beforeAfterRow(_ title: String, _ result: CriterionResult, faded: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Text(title)
                    .font(Typeface.label(14))
                    .foregroundStyle(faded ? Palette.muted : Palette.ink)
                Spacer()
                LevelPill(level: result.level, faded: faded)
            }
            if let quote = result.evidence.first?.quote {
                SpeechBubble(text: AttributedString(quote), speaker: .user, size: 15)
                    .opacity(faded ? 0.7 : 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, Space.xxl)
            }
        }
    }

    /// Words, not a bare number: a score out of 100 means nothing on its own.
    static func band(_ score: Int) -> String {
        score >= 75 ? String(localized: "Strong", bundle: AppLanguage.bundle) : score >= 50 ? String(localized: "Getting there", bundle: AppLanguage.bundle) : String(localized: "Needs work", bundle: AppLanguage.bundle)
    }

    /// A quote cut from a longer line gets an ellipsis at each cut end, so a
    /// fragment never reads as everything that was said.
    static func excerpt(_ quote: String, of line: String?) -> String {
        let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line, let range = line.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) else { return trimmed }
        let before = line[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let after = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return (before.isEmpty ? "" : "…") + trimmed + (after.isEmpty ? "" : "…")
    }

    // MARK: Pieces

    /// A section as on the main tabs: its title above, one glass card below.
    private func card<Content: View>(title: String, surface: Color? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionTitle(text: title)
            VStack(alignment: .leading, spacing: Space.md) { content() }
                .padding(Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(cornerRadius: Corner.lg, tint: surface)
        }
    }

    /// The user's own words as they appear in the chat — right-hand, coral —
    /// so a quote reads as something said, not a citation. Tapping it shows
    /// the line in the conversation.
    private func quote(_ evidence: CriterionResult.Evidence) -> some View {
        let line = report.transcript.first { $0.id == evidence.turnId }
        return bubbleButton(lineID: line?.id) {
            SpeechBubble(text: AttributedString(Self.excerpt(evidence.quote, of: line?.text)), speaker: .user, size: 15)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, Space.xxl)
    }

    @ViewBuilder
    private func bubbleButton<Label: View>(lineID: String?, @ViewBuilder label: () -> Label) -> some View {
        if let lineID {
            Button { show(lineID) } label: { label() }
                .buttonStyle(BubblePressStyle())
                .accessibilityHint("Shows this line in the conversation")
        } else {
            label()
        }
    }
}

// MARK: - Components

/// Feedback | Conversation: a glass capsule with the choice drawn inside it
/// (inside a glass container, overlays get absorbed).
private struct DebriefTabs: View {
    @Binding var selection: DebriefView.Tab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            segment(String(localized: "Feedback", bundle: AppLanguage.bundle), .feedback)
            segment(String(localized: "Conversation", bundle: AppLanguage.bundle), .conversation)
        }
        .padding(4)
        .glassSurface(cornerRadius: 22)
    }

    private func segment(_ title: String, _ tab: DebriefView.Tab) -> some View {
        let isSelected = selection == tab
        return Button {
            guard !isSelected else { return }
            Haptics.selection()
            withAnimation(.snappy(duration: 0.3)) { selection = tab }
        } label: {
            Text(title)
                .font(Typeface.label(15))
                .foregroundStyle(isSelected ? Palette.ink : Palette.dim)
                .padding(.horizontal, Space.lg)
                .frame(height: 36)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Palette.paper)
                            .shadow(color: Palette.ink.opacity(0.08), radius: 6, y: 2)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One line of speech. The partner speaks from the left on paper; the user
/// from the right on coral. The same bubble quotes a line inside a card, so
/// the feedback and the conversation share one look.
private struct SpeechBubble: View {
    enum Speaker { case user, partner }

    let text: AttributedString
    let speaker: Speaker
    var size: CGFloat = 16
    var isSpotlit = false

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: speaker == .partner ? 6 : 18,
            bottomTrailingRadius: speaker == .user ? 6 : 18,
            topTrailingRadius: 18,
            style: .continuous
        )
        Text(text)
            .font(Typeface.body(size))
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(speaker == .user ? Palette.glassCoral : Palette.paper.opacity(0.9), in: shape)
            .overlay {
                shape.strokeBorder(
                    isSpotlit ? Palette.coral : speaker == .partner ? Palette.border : .clear,
                    lineWidth: isSpotlit ? 2 : 1
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(speaker == .user
                ? String(localized: "You: \(String(text.characters))", bundle: AppLanguage.bundle)
                : String(localized: "Partner: \(String(text.characters))", bundle: AppLanguage.bundle))
    }
}

private struct BubblePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// A small icon-and-words tag under a line or above a quote.
private struct MarkLabel: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
            Text(text).font(Typeface.label(12))
        }
        .foregroundStyle(color)
    }
}

/// A criterion's level in one plain word on a soft pill: Clearly (sage),
/// Partly (coral), Not yet (grey). Words, not symbols: the dashed and
/// half-filled marks this replaced needed a legend nobody had.
struct LevelPill: View {
    let level: Int
    var faded = false

    static func name(_ level: Int) -> String {
        [String(localized: "Not yet", bundle: AppLanguage.bundle), String(localized: "Partly", bundle: AppLanguage.bundle), String(localized: "Clearly", bundle: AppLanguage.bundle)][min(max(level, 0), 2)]
    }

    static func color(_ level: Int) -> Color {
        [Palette.muted, Palette.coralDeep, Palette.sage][min(max(level, 0), 2)]
    }

    var body: some View {
        let color = faded ? Palette.muted : Self.color(level)
        Text(Self.name(level))
            .font(Typeface.label(13))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
            .fixedSize()
            .accessibilityLabel([String(localized: "Not yet shown", bundle: AppLanguage.bundle), String(localized: "Partly shown", bundle: AppLanguage.bundle), String(localized: "Clearly shown", bundle: AppLanguage.bundle)][min(max(level, 0), 2)])
    }
}

/// A thin coral bar, 0…1.
private struct ScoreBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [Palette.peach, Palette.coral], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
