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

// MARK: - The mirror

/// The user's own answers handed back as a named pattern. Every quote under
/// it is something they said "That's me" to — nothing asserted they didn't
/// tell us. The diagnosis types out; Continue waits for it.
struct MirrorInstrument: View {
    let pattern: SpeakingPattern
    let evidence: [PainStatement]
    @Binding var ready: Bool

    var body: some View {
        VStack(spacing: Space.xxl) {
            Text(pattern.name)
                .font(Typeface.hero(40))
                .foregroundStyle(Palette.coralDeep)
                .revealIn(after: 0.1, rise: 14)

            NarrativePage(lines: [pattern.diagnosis], ready: $ready, fontSize: 21)
                .fixedSize(horizontal: false, vertical: true)

            if !evidence.isEmpty {
                VStack(spacing: Space.sm) {
                    Kicker(text: "You said", color: Palette.muted)
                    ForEach(Array(evidence.prefix(2)), id: \.self) { statement in
                        Text("“\(statement.text)”")
                            .font(Typeface.bodyItalic(15))
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Space.lg)
                            .padding(.vertical, Space.md)
                            .frame(maxWidth: .infinity)
                            .glassSurface(cornerRadius: Corner.md)
                    }
                }
                .opacity(ready ? 1 : 0)
                .offset(y: ready ? 0 : 8)
                .animation(.easeOut(duration: 0.5), value: ready)
            }
        }
    }
}

// MARK: - The demo

/// "Practice it before it's real", shown rather than told: a rehearsal in
/// miniature under the user's thumb. Three beats, the product's own loop:
///
/// 1. **Rehearse** — hold the bloom and the first take streams out word by
///    word, a haptic on each, the petals opening with the "voice".
/// 2. **Hear it back** — the fillers light up, then lift off one by one with
///    a crisp tap each, and the sentence closes up around the gaps.
/// 3. **Retry** — hold again, and the better take lands; the fix for their
///    own pattern settles underneath.
///
/// Letting go mid-take pauses it (the petals fold); holding resumes. The
/// bloom is the same instrument as the rehearsal room's, so the first time
/// they see it breathe with a voice is here. VoiceOver's activate plays a
/// whole take; Reduce Motion keeps every beat, without the travel.
struct DemoInstrument: View {
    let script: DemoScript
    let fix: String
    @Binding var ready: Bool

    enum Beat: Int, CaseIterable {
        case rehearse, hearBack, retry, done

        var label: String {
            switch self {
            case .rehearse: "Rehearse"
            case .hearBack: "Hear it back"
            case .retry, .done: "Retry"
            }
        }
    }

    @State private var beat: Beat = .rehearse
    @State private var shown: [DemoScript.Word] = []
    @State private var cursor = 0
    @State private var flagged: Set<Int> = []
    @State private var holding = false
    @State private var level: Double = 0
    @State private var speaking: Task<Void, Never>?
    @State private var coaching: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var take: [DemoScript.Word] { beat == .rehearse ? script.firstWords : script.betterWords }
    private var canHold: Bool { (beat == .rehearse || beat == .retry) && cursor < take.count }

    var body: some View {
        VStack(spacing: Space.xl) {
            beats
            card
            bloom
        }
        .onDisappear { stopSpeaking(); coaching?.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { release() } }
    }

    // MARK: Beats

    private var beats: some View {
        HStack(spacing: Space.sm) {
            ForEach([Beat.rehearse, .hearBack, .retry], id: \.self) { item in
                if item != .rehearse {
                    Circle().fill(Palette.faint).frame(width: 3, height: 3)
                }
                Text(item.label)
                    .font(Typeface.label(13))
                    .foregroundStyle(color(for: item))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: beat)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step: \(beat.label)")
    }

    private func color(for item: Beat) -> Color {
        let current = beat == .done ? Beat.retry : beat
        if item == current { return Palette.coralDeep }
        return item.rawValue < current.rawValue ? Palette.ink : Palette.muted
    }

    // MARK: The card

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Kicker(text: script.partner, color: Palette.muted)
            Text(script.prompt)
                .font(Typeface.title(20))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            GlassRowDivider()
            ZStack(alignment: .topLeading) {
                if shown.isEmpty {
                    Text(beat == .retry ? "Now say it again." : "Your answer appears here.")
                        .font(Typeface.bodyItalic(16))
                        .foregroundStyle(Palette.muted)
                        .transition(.opacity)
                }
                FlowLayout(spacing: 5, lineSpacing: 6) {
                    ForEach(shown) { word in
                        Text(word.text)
                            .font(Typeface.body(17))
                            .foregroundStyle(flagged.contains(word.id) ? Palette.coralDeep : Palette.ink)
                            .strikethrough(flagged.contains(word.id), color: Palette.coral)
                            .transition(wordTransition)
                    }
                }
            }
            // Room for the longest take and a two-line caption, reserved up
            // front: the card must not grow while a thumb is on the bloom
            // below it, or the bloom slides out from under the finger.
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shown.map(\.text).joined(separator: " "))

            ZStack(alignment: .topLeading) {
                if let caption {
                    Text(caption)
                        .font(Typeface.label(14))
                        .foregroundStyle(beat == .done ? Palette.sage : Palette.coralDeep)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(caption)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Corner.xl)
        .animation(.easeOut(duration: 0.3), value: caption)
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

    private var caption: String? {
        switch beat {
        case .rehearse: nil
        case .hearBack: flagged.isEmpty ? nil : "\(script.fillerCount) fillers. \(script.note)"
        case .retry: script.note
        case .done: fix
        }
    }

    // MARK: The bloom

    private var bloom: some View {
        VStack(spacing: Space.md) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(holding ? 0.75 : 0.5))
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                    .frame(width: 104, height: 104)
                BloomMark(size: 60, level: level)
            }
            .frame(width: 124, height: 124)
            .scaleEffect(holding ? 0.96 : 1)
            .opacity(canHold || holding || beat == .done ? 1 : 0.55)
            .animation(.easeOut(duration: 0.18), value: holding)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if abs(value.translation.width) > 80 || abs(value.translation.height) > 80 {
                            release()
                        } else if !holding {
                            press()
                        }
                    }
                    .onEnded { _ in release() }
            )
            .accessibilityElement()
            .accessibilityLabel(holdCaption)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { playWholeTake() }

            Text(holdCaption)
                .font(Typeface.label(16))
                .foregroundStyle(beat == .done ? Palette.coralDeep : Palette.dim)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: holdCaption)
        }
    }

    private var holdCaption: String {
        switch beat {
        case .rehearse: holding ? "Keep holding…" : cursor == 0 ? "Hold to answer" : "Hold to keep going"
        case .hearBack: "Hearing it back…"
        case .retry: holding ? "Keep holding…" : cursor == 0 ? "Hold to try again" : "Hold to keep going"
        case .done: "Much clearer."
        }
    }

    // MARK: Playing

    private func press() {
        guard canHold, speaking == nil else { return }
        holding = true
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
        withAnimation(.easeOut(duration: 0.12)) { level = Double.random(in: 0.45...0.95) }
    }

    private func release() {
        stopSpeaking()
        guard holding else { return }
        holding = false
        withAnimation(.easeOut(duration: 0.35)) { level = 0 }
    }

    private func stopSpeaking() {
        speaking?.cancel()
        speaking = nil
    }

    /// VoiceOver has no hold to give: activating plays the take in full.
    private func playWholeTake() {
        guard canHold else { return }
        stopSpeaking()
        while cursor < take.count { speak(take[cursor]) }
        finishTake()
    }

    private func finishTake() {
        speaking = nil
        holding = false
        withAnimation(.easeOut(duration: 0.35)) { level = 0 }
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
                shown = []
                flagged = []
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
                    Kicker(text: "First rehearsal · \(practice?.durationMinutes ?? 4) min", color: Palette.coralDeep)
                    Text(practice?.title ?? "Your first rehearsal")
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
