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

// MARK: - How it works

/// Three beats, the third written for the user's own pattern.
struct HowItWorksInstrument: View {
    let pattern: SpeakingPattern
    @Binding var ready: Bool

    private var beats: [(icon: String, title: String, line: String)] {
        [
            ("mic.fill", "Rehearse it", "A partner plays the other side — out loud."),
            ("quote.bubble.fill", "Hear it back", "Feedback that quotes your own words."),
            ("arrow.counterclockwise", "Retry the moment", pattern.fix),
        ]
    }

    var body: some View {
        VStack(spacing: Space.md) {
            ForEach(Array(beats.enumerated()), id: \.offset) { offset, beat in
                HStack(alignment: .top, spacing: Space.md) {
                    GlassRowIcon(icon: beat.icon)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(beat.title)
                            .font(Typeface.label(17))
                            .foregroundStyle(Palette.ink)
                        Text(beat.line)
                            .font(Typeface.body(15))
                            .foregroundStyle(Palette.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.lg)
                .glassSurface(cornerRadius: Corner.lg)
                .revealIn(after: 0.3 + Double(offset) * 0.55, rise: 12)
            }
        }
        .after(1.9) { ready = true }
    }
}

// MARK: - Try it

/// A twenty-second taste of the coaching before the voice session that sits
/// behind the paywall: pick the opening that lands, and see why in one line.
struct TryItInstrument: View {
    let quiz: OpeningQuiz
    @Binding var choice: Int?

    var body: some View {
        VStack(spacing: Space.lg) {
            GlassGroup(spacing: Space.md) {
                VStack(spacing: Space.md) {
                    ForEach(Array(quiz.options.enumerated()), id: \.offset) { index, option in
                        QuizOption(text: option, state: state(for: index)) {
                            guard choice == nil else { return }
                            choice = index
                            if index == quiz.bestIndex { Haptics.success() } else { Haptics.rigid() }
                        }
                    }
                }
            }

            if let choice {
                VStack(spacing: Space.xs) {
                    Text(choice == quiz.bestIndex ? "Exactly." : "Close — the best one is marked.")
                        .font(Typeface.label(16))
                        .foregroundStyle(choice == quiz.bestIndex ? Palette.sage : Palette.coralDeep)
                    Text(quiz.why)
                        .font(Typeface.body(15))
                        .foregroundStyle(Palette.dim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(.easeOut(duration: 0.35), value: choice)
    }

    private func state(for index: Int) -> QuizOption.State {
        guard let choice else { return .open }
        if index == quiz.bestIndex { return .best }
        return index == choice ? .missed : .dimmed
    }
}

private struct QuizOption: View {
    enum State { case open, best, missed, dimmed }

    let text: String
    let state: State
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            HStack(alignment: .center, spacing: Space.md) {
                Text(text)
                    .font(Typeface.body(16))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: state == .best ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(state == .best ? Palette.sage : Palette.faint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.lg)
            .contentShape(RoundedRectangle(cornerRadius: Corner.xl, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: Corner.xl, interactive: state == .open)
        .overlay {
            RoundedRectangle(cornerRadius: Corner.xl, style: .continuous)
                .strokeBorder(state == .best ? Palette.sage : state == .missed ? Palette.coral.opacity(0.5) : .clear, lineWidth: 1.2)
        }
        .opacity(state == .dimmed ? 0.5 : 1)
        .disabled(state != .open)
        .animation(.easeOut(duration: 0.3), value: state)
    }
}

// MARK: - The plan

/// The outcome made concrete: *this* rehearsal, the retry, then the moment
/// itself — in the user's own words.
struct PlanInstrument: View {
    let answers: OnboardingAnswers
    @Binding var language: String
    @Binding var ready: Bool

    private var moment: SpeakingMoment { answers.moment ?? .interview }
    private var practice: PracticeDefinition? { PracticeCatalog.definition(moment.firstPracticeID) }

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

            HStack {
                if answers.readinessTouched {
                    Text("Readiness today: \(answers.readiness)/10")
                        .font(Typeface.body(14))
                        .foregroundStyle(Palette.dim)
                }
                Spacer()
                Menu {
                    Picker("Practice language", selection: $language) {
                        ForEach(PracticeLanguage.all) { Text($0.name).tag($0.id) }
                    }
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "globe")
                        Text(PracticeLanguage.named(language))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .font(Typeface.label(14))
                    .foregroundStyle(Palette.coralDeep)
                }
                .accessibilityLabel("Practice language, \(PracticeLanguage.named(language))")
            }
            .revealIn(after: 0.8)
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
