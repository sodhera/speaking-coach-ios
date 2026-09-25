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
                        // Centred like an album page, so the cover, title
                        // and goal balance the full-width card below.
                        VStack(spacing: 0) {
                            SessionCover(symbol: HomeSection.containing(practice)?.icon ?? "mic", size: 112)

                            Text(practice.title)
                                .font(Typeface.hero(28))
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, Space.xl)
                            Text(practice.objective)
                                .font(Typeface.body(16))
                                .foregroundStyle(Palette.dim)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, Space.sm)
                                .padding(.horizontal, Space.lg)
                        }
                        .frame(maxWidth: .infinity)

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
        // A page with its own action at the bottom: the tab bar steps aside.
        .toolbar(.hidden, for: .tabBar)
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
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: 44, minHeight: 44)
                }
                .padding(.top, Space.lg)
                .padding(.bottom, Space.xl)
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
            // The situation as one card, its question inside, like the
            // presentation's audience card.
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Your situation")
                    .font(Typeface.label(13))
                    .foregroundStyle(Palette.muted)
                TextField(
                    "",
                    text: $setup.situation,
                    prompt: Text("Optional · e.g. it's a product role at a startup").foregroundStyle(Palette.faint),
                    axis: .vertical
                )
                .lineLimit(2...5)
                .font(Typeface.body(16))
                .foregroundStyle(Palette.ink)
                .tint(Palette.coral)
                .focused($situationFocused)
                .onChange(of: setup.situation) { _, text in
                    if text.count > 1200 { setup.situation = String(text.prefix(1200)) }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { situationFocused = true }
            .glassSurface(cornerRadius: Corner.lg)
            Segmented(title: "Pressure", options: PracticeSetup.Pressure.allCases, selection: $setup.pressure, label: pressureName)
            Segmented(title: "Pace", options: PracticeSetup.Pacing.allCases, selection: $setup.pacing) {
                $0 == .patient ? "Time to think" : "Natural"
            }
            Segmented(title: "Partner's voice", options: PracticeSetup.Persona.allCases, selection: $setup.persona) {
                $0 == .female ? "Female" : "Male"
            }
        }
    }
}

/// The app's segmented control is Apple's own, so on iOS 26 the choice is
/// the system's Liquid Glass thumb. You can hold it and drag it across, and
/// it stretches and ticks as it goes; a custom look-alike could never do
/// that. We only restyle its words: DM Sans, and the chosen word in coral,
/// the control's one accent. The thumb stays the system's own; a tinted
/// thumb read as pink.
struct Segmented<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    init(title: String, options: [Option], selection: Binding<Option>, label: @escaping (Option) -> String) {
        self.title = title
        self.options = options
        _selection = selection
        self.label = label
        _ = SegmentedAppearance.applied
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(Typeface.label(14))
                .foregroundStyle(Palette.dim)
                .padding(.leading, Space.xs)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .sensoryFeedback(.selection, trigger: selection)
        }
    }
}

/// DM Sans on every segmented control, set once. The system draws the rest.
private enum SegmentedAppearance {
    static let applied: Void = {
        let control = UISegmentedControl.appearance()
        // Warm paper, not the system's bright white: a pure-white thumb
        // glared against the warm ground.
        control.selectedSegmentTintColor = UIColor(Palette.skyHigh)
        control.setTitleTextAttributes([
            .font: Typeface.uiFont(size: 15, weight: 450),
            .foregroundColor: UIColor(Palette.dim),
        ], for: .normal)
        control.setTitleTextAttributes([
            .font: Typeface.uiFont(size: 15, weight: 550),
            .foregroundColor: UIColor(Palette.coralDeep),
        ], for: .selected)
    }()
}
