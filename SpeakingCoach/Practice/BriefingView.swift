import SwiftUI

/// How a rehearsal is set up — exactly the fields `/api/practice/start` takes.
struct PracticeSetup: Hashable, Identifiable {
    enum Pressure: String, CaseIterable { case supportive, realistic, challenging }
    enum Pacing: String, CaseIterable { case patient, normal }
    enum Persona: String, CaseIterable { case female, male }

    let practice: PracticeDefinition
    var pressure: Pressure
    var pacing: Pacing = .patient
    var persona: Persona
    var situation = ""

    var id: String { practice.id }
}

/// The moment before a rehearsal: what it is, who you'll talk to, and — only
/// if you want — the knobs. One button starts it.
struct BriefingView: View {
    let practice: PracticeDefinition
    let onBack: () -> Void
    let onStart: (PracticeSetup) -> Void

    @State private var setup: PracticeSetup
    @State private var adjusting = false
    @FocusState private var situationFocused: Bool

    init(practice: PracticeDefinition, onBack: @escaping () -> Void, onStart: @escaping (PracticeSetup) -> Void) {
        self.practice = practice
        self.onBack = onBack
        self.onStart = onStart
        // The first gentle practice never pressures; everything else starts realistic.
        let pressure: PracticeSetup.Pressure = practice.format == "guided" ? .supportive : .realistic
        _setup = State(initialValue: PracticeSetup(practice: practice, pressure: pressure, persona: .female))
    }

    var body: some View {
        ZStack {
            MorningStage(depth: 0.4, ripples: false)
            VStack(spacing: 0) {
                HStack {
                    GlassBackButton(action: onBack)
                    Spacer()
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.sm)

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        VStack(alignment: .leading, spacing: Space.md) {
                            Kicker(text: "\(practice.durationMinutes) min rehearsal")
                            Text(practice.title)
                                .font(Typeface.hero(34))
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(practice.objective)
                                .font(Typeface.body(17))
                                .foregroundStyle(Palette.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: Space.sm) {
                            partnerCard
                            QuietButton(title: "Adjust this rehearsal", color: Palette.coralDeep) {
                                adjusting = true
                            }
                        }
                    }
                    .padding(.horizontal, Space.xxl)
                    .padding(.top, Space.xl)
                    .padding(.bottom, Space.xl)
                }
                .scrollDismissesKeyboard(.interactively)

                PrimaryButton(title: "Start speaking", systemImage: "mic.fill") {
                    situationFocused = false
                    Analytics.action("briefing")
                    var final = setup
                    final.situation = setup.situation.trimmingCharacters(in: .whitespacesAndNewlines)
                    onStart(final)
                }
                .padding(.horizontal, Space.xxl)
                .padding(.bottom, Space.sm)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Analytics.enter("briefing") }
        .sheet(isPresented: $adjusting) {
            SceneScreen(depth: 0.4) {
                HStack {
                    Text("Adjust rehearsal")
                        .font(Typeface.hero(28))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Button("Done") {
                        situationFocused = false
                        adjusting = false
                    }
                    .font(Typeface.label(16))
                    .foregroundStyle(Palette.coralDeep)
                }
                .padding(.top, Space.lg)
                .padding(.bottom, Space.xxl)
                adjustments
            }
            .presentationDragIndicator(.visible)
        }
    }

    private var partnerCard: some View {
        HStack(spacing: Space.lg) {
            ZStack {
                Circle().fill(Palette.coral.opacity(0.14))
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.coralDeep)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your partner")
                    .font(Typeface.label(13))
                    .foregroundStyle(Palette.muted)
                Text(practice.partner)
                    .font(Typeface.title(17))
                    .foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.lg)
        .glassSurface(cornerRadius: Corner.lg)
    }

    // MARK: Adjustments

    private var adjustments: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.sm) {
                label("Your situation")
                TextField(
                    "",
                    text: $setup.situation,
                    prompt: Text("e.g. It's a product role at a startup").foregroundStyle(Palette.muted),
                    axis: .vertical
                )
                .lineLimit(2...5)
                .font(Typeface.body(16))
                .foregroundStyle(Palette.ink)
                .tint(Palette.coral)
                .focused($situationFocused)
                .padding(Space.lg)
                .glassSurface(cornerRadius: Corner.md, interactive: true)
                .onChange(of: setup.situation) { _, text in
                    if text.count > 1200 { setup.situation = String(text.prefix(1200)) }
                }
            }
            Segmented(title: "Pressure", options: PracticeSetup.Pressure.allCases, selection: $setup.pressure) {
                switch $0 {
                case .supportive: "Gentle"
                case .realistic: "Realistic"
                case .challenging: "Tough"
                }
            }
            Segmented(title: "Pace", options: PracticeSetup.Pacing.allCases, selection: $setup.pacing) {
                $0 == .patient ? "Time to think" : "Natural"
            }
            Segmented(title: "Partner's voice", options: PracticeSetup.Persona.allCases, selection: $setup.persona) {
                $0 == .female ? "Female" : "Male"
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Typeface.label(14)).foregroundStyle(Palette.dim)
    }
}

/// A row of glass capsules, one selected — the app's segmented control.
struct Segmented<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title).font(Typeface.label(14)).foregroundStyle(Palette.dim)
            GlassGroup(spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    ForEach(options, id: \.self) { option in
                        let isSelected = option == selection
                        Button {
                            Haptics.selection()
                            selection = option
                        } label: {
                            Text(label(option))
                                .font(Typeface.label(15))
                                .foregroundStyle(isSelected ? .white : Palette.ink)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                // Selection is drawn inside the glass: inside
                                // a glass container, overlays get absorbed.
                                .background(Capsule().fill(Palette.coral.opacity(isSelected ? 1 : 0)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(SegmentStyle(isSelected: isSelected))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }
}

private struct SegmentStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassSurface(cornerRadius: 22, interactive: true)
            .animation(.easeOut(duration: 0.18), value: isSelected)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
