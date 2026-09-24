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

/// The moment before a session, laid out like a track's page: its cover,
/// the title and goal, then the setup as a short list. The knobs are the
/// list's last row, only if you want them. One button starts it.
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
                    VStack(alignment: .leading, spacing: 0) {
                        SessionCover(symbol: PracticeCategory(rawValue: practice.category)?.icon ?? "mic.fill", size: 88)

                        Text(practice.title)
                            .font(Typeface.hero(30))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Space.xl)
                        Text(practice.objective)
                            .font(Typeface.body(16))
                            .foregroundStyle(Palette.dim)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Space.sm)

                        details
                            .padding(.top, Space.xxl)
                    }
                    .padding(.horizontal, Space.xxl)
                    .padding(.top, Space.lg)
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
                    Text("Adjust session")
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

    /// The setup as a short list, like a track's details: who, how long,
    /// how hard. Adjust is the last row, so the knobs stay one tap away and
    /// out of the way.
    private var details: some View {
        GlassRowGroup {
            detailRow("Partner", practice.partner)
            GlassRowDivider()
            detailRow("Length", "\(practice.durationMinutes) min")
            GlassRowDivider()
            detailRow("Pressure", pressureName(setup.pressure))
            let situation = setup.situation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !situation.isEmpty {
                GlassRowDivider()
                detailRow("Your situation", situation)
            }
            GlassRowDivider()
            Button {
                Haptics.selection()
                adjusting = true
            } label: {
                HStack(spacing: Space.sm) {
                    Text("Adjust session")
                        .font(Typeface.label(15))
                        .foregroundStyle(Palette.coralDeep)
                    Spacer(minLength: Space.sm)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.faint)
                }
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.lg) {
            Text(label)
                .font(Typeface.body(15))
                .foregroundStyle(Palette.dim)
            Spacer(minLength: Space.sm)
            Text(value)
                .font(Typeface.label(15))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, Space.md)
        .frame(minHeight: 50)
        .accessibilityElement(children: .combine)
    }

    private func pressureName(_ pressure: PracticeSetup.Pressure) -> String {
        switch pressure {
        case .supportive: "Gentle"
        case .realistic: "Realistic"
        case .challenging: "Tough"
        }
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
            Segmented(title: "Pressure", options: PracticeSetup.Pressure.allCases, selection: $setup.pressure, label: pressureName)
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
