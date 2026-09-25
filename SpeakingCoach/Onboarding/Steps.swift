import SwiftUI

// The instruments that sit under each onboarding question. Titles, spacing
// and the bottom action belong to `QuestionLayout` and `OnboardingFlow`; these
// only draw the control or the reveal.

// MARK: - Name

/// A lone hero field with the keyboard up, so an editorial underline rather
/// than a glass box. The idle rule is `faint`, not `hairline` — a 7% rule
/// vanishes into the stage and the field reads as bare text.
struct NameField: View {
    @Binding var name: String
    let onSubmit: () -> Void

    @FocusState private var focused: Bool
    @State private var focusTask: Task<Void, Never>?

    var body: some View {
        TextField("Your first name", text: $name, prompt: Text("Your first name").foregroundStyle(Palette.muted))
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .multilineTextAlignment(.center)
            .font(Typeface.title(24))
            .foregroundStyle(Palette.ink)
            .tint(Palette.coral)
            .padding(.vertical, Space.md)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(focused ? Palette.coral.opacity(0.6) : Palette.faint)
                    .frame(height: 1)
            }
            .focused($focused)
            .onSubmit(onSubmit)
            .accessibilityLabel("Your first name")
            .onAppear {
                focusTask?.cancel()
                focusTask = Task { @MainActor in
                    // Wait out the step fade so the keyboard doesn't stutter it.
                    try? await Task.sleep(for: .milliseconds(320))
                    guard !Task.isCancelled else { return }
                    focused = true
                }
            }
            .onDisappear {
                focusTask?.cancel()
                focused = false
            }
    }
}

// MARK: - The deck

/// "Does this sound like you?" — the pain beat. The question stays put while
/// six statements pass under it one at a time, each answered with the flow's
/// ordinary answer rows. The user isn't told they have a problem; they
/// recognise it, one sentence at a time.
struct DeckInstrument: View {
    let index: Int
    let selected: Agreement?
    let onAnswer: (Agreement) -> Void

    private var statement: PainStatement { PainStatement.allCases[min(index, PainStatement.allCases.count - 1)] }

    var body: some View {
        VStack(spacing: Space.xxl) {
            Text("“\(statement.text)”")
                .font(Typeface.title(22))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.xxl)
                .frame(maxWidth: .infinity, minHeight: 150)
                .glassSurface(cornerRadius: Corner.xl)
                .id(statement)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))

            GlassGroup(spacing: Space.md) {
                VStack(spacing: Space.md) {
                    OptionRow(icon: "checkmark", title: "That's me", isSelected: selected == .yes) { onAnswer(.yes) }
                    OptionRow(icon: "circle.lefthalf.filled", title: "Sometimes", isSelected: selected == .sometimes) { onAnswer(.sometimes) }
                    OptionRow(icon: "xmark", title: "Not me", isSelected: selected == .no) { onAnswer(.no) }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: index)
    }
}

// MARK: - Support

/// A caring response and a concrete next step, tailored privately from the
/// answers without labeling the person or repeating their selections. The
/// two sentences type out in turn, with the promise page's word haptics.
struct MirrorInstrument: View {
    let pattern: SpeakingPattern
    @Binding var ready: Bool

    var body: some View {
        VStack(spacing: Space.xl) {
            BloomMark(size: 80, glow: false)
                .revealIn(after: 0.1)

            // Typed word by word with a tick per word, like the promise
            // page: this is the app speaking to them, not a caption.
            TypedParagraphs(
                lines: [
                    .init(text: pattern.encouragement, size: 25),
                    .init(text: pattern.practiceHelp, size: 17, weight: 400, color: Palette.dim),
                ],
                delay: .milliseconds(650),
                onFinished: { ready = true }
            )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - The demo

/// A tappable example of the practice loop, shown as a two-line chat: the
/// partner's question, then an example answer (labelled as one) that plays
/// in, gets one change, and plays again with it. Nothing to read up front;
/// the user does not speak on this page.
///
/// One tap shows a first try and one useful change. A second tap shows the
/// clearer try. Reduce Motion keeps the steps without word travel.
struct DemoInstrument: View {
    let script: DemoScript
    @Binding var ready: Bool

    enum Beat: Int, CaseIterable {
        case rehearse, hearBack, retry, done
    }

    @State private var beat: Beat = .rehearse
    @State private var shown: [DemoScript.Word] = []
    @State private var cursor = 0
    @State private var flagged: Set<Int> = []
    @State private var isPlaying = false
    @State private var speaking: Task<Void, Never>?
    @State private var coaching: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var take: [DemoScript.Word] { beat == .rehearse ? script.firstWords : script.betterWords }
    private var canPlay: Bool { (beat == .rehearse || beat == .retry) && cursor < take.count }

    var body: some View {
        VStack(spacing: Space.xl) {
            conversation
            // Always laid out, only hidden: removing it at the end re-centred
            // the page and the conversation jumped.
            PrimaryButton(title: actionTitle, systemImage: "play.fill", action: playTake)
                .disabled(!canPlay || isPlaying)
                .opacity(beat == .hearBack || beat == .done ? 0 : 1)
                .accessibilityHidden(beat == .hearBack || beat == .done)
        }
        .onDisappear { stopSpeaking(); coaching?.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopSpeaking() } }
    }

    // MARK: The conversation

    /// The example as a two-line chat, in the feedback's bubble language:
    /// the partner asks on the left, the example answer arrives on the right.
    /// Its room is reserved up front, so nothing moves while a thumb is on
    /// the button below.
    private var conversation: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text(script.partner)
                    .font(Typeface.label(12))
                    .foregroundStyle(Palette.muted)
                    .padding(.leading, Space.xs)
                Text(script.prompt.trimmingCharacters(in: CharacterSet(charactersIn: "“”\"")))
                    .font(Typeface.body(17))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Palette.paper, in: bubble(from: .partner))
                    .overlay { bubble(from: .partner).strokeBorder(Palette.border, lineWidth: 1) }
            }
            .padding(.trailing, Space.huge)

            VStack(alignment: .trailing, spacing: 6) {
                if !shown.isEmpty {
                    Text("Example answer")
                        .font(Typeface.label(12))
                        .foregroundStyle(Palette.muted)
                        .padding(.trailing, Space.xs)
                        .transition(.opacity)
                    FlowLayout(spacing: 5, lineSpacing: 6) {
                        ForEach(shown) { word in
                            Text(word.text)
                                .font(Typeface.body(17))
                                .foregroundStyle(flagged.contains(word.id) ? Palette.coralDeep : Palette.ink)
                                .strikethrough(flagged.contains(word.id), color: Palette.coral)
                                .transition(wordTransition)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Palette.glassCoral, in: bubble(from: .user))
                    .transition(.opacity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(shown.map(\.text).joined(separator: " "))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topTrailing)
            .padding(.leading, Space.xxl)

            ZStack {
                if let caption {
                    Text(caption)
                        .font(Typeface.label(15))
                        .foregroundStyle(beat == .done ? Palette.sage : Palette.coralDeep)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(caption)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .animation(.easeOut(duration: 0.3), value: caption)
        .animation(.easeOut(duration: 0.25), value: shown.isEmpty)
    }

    private enum Side { case partner, user }

    private func bubble(from side: Side) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: side == .partner ? 6 : 18,
            bottomTrailingRadius: side == .user ? 6 : 18,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    /// Words arrive with a small rise; fillers leave upward and shrink, as
    /// if lifted off the line.
    private var wordTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 5)),
                removal: .opacity.combined(with: .scale(scale: 0.4)).combined(with: .offset(y: -14))
            )
    }

    /// One short line, only when there's something to say.
    private var caption: String? {
        switch beat {
        case .rehearse: nil
        case .hearBack, .retry: flagged.isEmpty ? nil : "One change: \(script.note)"
        case .done: "Your words, one change, a clearer try."
        }
    }

    private var actionTitle: String {
        switch beat {
        case .rehearse: "Play an example"
        case .hearBack: "Finding one change…"
        case .retry: "Play with better phrasing"
        case .done: "Play it with the change"
        }
    }

    // MARK: Playing

    private func playTake() {
        guard canPlay, speaking == nil else { return }
        if beat == .retry {
            withAnimation(.easeOut(duration: 0.2)) {
                shown = []
                flagged = []
            }
        }
        isPlaying = true
        Haptics.prepare()
        Haptics.soft()
        speaking = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(140))
                while cursor < take.count {
                    try Task.checkCancellation()
                    speak(take[cursor])
                    // A voice has rhythm: short words are quick, fillers
                    // quicker, and a comma or full stop takes a breath.
                    let word = take[cursor - 1]
                    let pause = word.text.last.map { ",.?—".contains($0) } == true ? 150 : 0
                    try await Task.sleep(for: .milliseconds((word.isFiller ? 120 : 150) + word.text.count * 14 + pause))
                }
                finishTake()
            } catch {}
        }
    }

    private func speak(_ word: DemoScript.Word) {
        withAnimation(.easeOut(duration: 0.18)) { shown.append(word) }
        cursor += 1
        Haptics.tick(word.isFiller ? 0.28 : 0.45)
    }

    private func stopSpeaking() {
        speaking?.cancel()
        speaking = nil
        isPlaying = false
    }

    private func finishTake() {
        speaking = nil
        isPlaying = false
        Haptics.rigid()
        if beat == .rehearse {
            coaching = Task { @MainActor in await hearItBack() }
        } else {
            beat = .done
            Haptics.success()
            ready = true
        }
    }

    /// The fillers light up in turn, then lift off in turn, and what's left
    /// closes up into the sentence they meant.
    private func hearItBack() async {
        do {
            try await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeInOut(duration: 0.3)) { beat = .hearBack }
            let fillers = shown.filter(\.isFiller)
            for filler in fillers {
                try await Task.sleep(for: .milliseconds(170))
                withAnimation(.easeOut(duration: 0.2)) { _ = flagged.insert(filler.id) }
                Haptics.tick(0.55)
            }
            try await Task.sleep(for: .milliseconds(900))
            for filler in fillers {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.82)) {
                    shown.removeAll { $0.id == filler.id }
                }
                Haptics.rigid()
                try await Task.sleep(for: .milliseconds(210))
            }
            try await Task.sleep(for: .milliseconds(1100))
            withAnimation(.easeInOut(duration: 0.35)) {
                cursor = 0
                beat = .retry
            }
        } catch {}
    }
}

/// Words laid out left to right, wrapping like text — but each word its own
/// view, so removing one lets the rest glide into the gap.
struct FlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for (index, x) in zip(row.indices, row.xs) {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var xs: [CGFloat] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let x = row.indices.isEmpty ? 0 : row.width + spacing
            if !row.indices.isEmpty, x + size.width > width {
                rows.append(row)
                row = Row(y: row.y + row.height + lineSpacing)
            }
            let placeX = row.indices.isEmpty ? 0 : row.width + spacing
            row.indices.append(index)
            row.xs.append(placeX)
            row.width = placeX + size.width
            row.height = max(row.height, size.height)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - The plan

/// The outcome made concrete: *this* rehearsal, the retry, then the moment
/// itself — in the user's own words.
struct PlanInstrument: View {
    let answers: OnboardingAnswers
    @Binding var ready: Bool

    private var moment: SpeakingMoment { answers.moment ?? .interview }
    private var practice: PracticeDefinition? { moment.firstPractice }

    private var finish: String {
        moment.planFinish(outcomes: SpeakingOutcome.allCases.filter(answers.outcomes.contains))
    }

    var body: some View {
        VStack(spacing: Space.lg) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Kicker(text: "First session · \(practice?.durationMinutes ?? 4) min", color: Palette.coralDeep)
                    Text(practice?.title ?? "Your first session")
                        .font(Typeface.hero(24))
                        .foregroundStyle(Palette.ink)
                    if let practice {
                        Text("With \(practice.partner.lowercasedFirst)")
                            .font(Typeface.body(15))
                            .foregroundStyle(Palette.dim)
                    }
                }
                .padding(Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)

                GlassRowDivider()

                VStack(alignment: .leading, spacing: Space.lg) {
                    PlanRow(number: 1, text: FirstPlan.Step.rehearse.title)
                    PlanRow(number: 2, text: FirstPlan.Step.retry.title)
                    PlanRow(number: 3, text: finish)
                }
                .padding(Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .glassSurface(cornerRadius: Corner.xl)
            .revealIn(after: 0.2, rise: 14)

            if answers.readinessTouched {
                Text("Readiness today: \(answers.readiness)/10")
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .revealIn(after: 0.8)
            }
        }
        .after(1.1) { ready = true }
    }
}

private struct PlanRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: Space.md) {
            Text("\(number)")
                .font(Typeface.label(14))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(number == 3 ? Palette.coral : Palette.ink.opacity(0.78)))
            Text(text)
                .font(Typeface.label(16))
                .foregroundStyle(Palette.ink)
        }
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
