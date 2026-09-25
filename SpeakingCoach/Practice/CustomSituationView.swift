import SwiftUI

/// "Custom situation": any conversation the catalog doesn't have. Two
/// questions — who, and what you need to say — then a quick check that
/// hands the scene back in one friendly line before the partner plays it.
struct CustomSituationView: View {
    let language: String
    let onBack: () -> Void
    let onStart: (CustomSituation, PracticeSetup) -> Void

    @State private var partner = ""
    @State private var description = ""
    @State private var pressure: PracticeSetup.Pressure = .realistic
    @State private var persona: PracticeSetup.Persona = .female
    @State private var checking = false
    @State private var confirmation: String?
    @State private var problem: String?
    @FocusState private var focus: Field?

    private enum Field { case partner, description }

    private var trimmedPartner: String { partner.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isComplete: Bool { !trimmedPartner.isEmpty && trimmedDescription.count >= 20 }

    var body: some View {
        ZStack {
            MorningStage(depth: 0.4)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        HStack {
                            GlassBackButton(action: onBack)
                            Spacer()
                        }
                        .padding(.top, Space.sm)

                        // Centred like the briefing, which this page is for
                        // a scene the user writes themselves.
                        VStack(spacing: 0) {
                            SessionCover(symbol: "square.and.pencil", size: 88)
                            Text("Custom situation")
                                .font(Typeface.hero(28))
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.center)
                                .padding(.top, Space.xl)
                            Text("Describe any conversation. Your partner plays the other side.")
                                .font(Typeface.body(16))
                                .foregroundStyle(Palette.dim)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, Space.sm)
                                .padding(.horizontal, Space.lg)
                        }
                        .frame(maxWidth: .infinity)

                        // Both questions in one card, each asked inside it, like
                        // the presentation's audience card.
                        GlassRowGroup {
                            question("Who will you be talking to?", focus: .partner) {
                                TextField("", text: $partner, prompt: Text("e.g. my landlord").foregroundStyle(Palette.faint))
                                    .focused($focus, equals: .partner)
                                    .submitLabel(.next)
                                    .onSubmit { focus = .description }
                            }
                            GlassRowDivider()
                            question("What do you need to say?", focus: .description) {
                                TextField(
                                    "",
                                    text: $description,
                                    prompt: Text("e.g. I need my deposit back, and they keep avoiding the subject.").foregroundStyle(Palette.faint),
                                    axis: .vertical
                                )
                                .lineLimit(2...8)
                                .focused($focus, equals: .description)
                                .onChange(of: description) { _, text in
                                    if text.count > 1200 { description = String(text.prefix(1200)) }
                                    confirmation = nil
                                    problem = nil
                                }
                            }
                        }

                        Segmented(title: "Pressure", options: PracticeSetup.Pressure.allCases, selection: $pressure) {
                            switch $0 {
                            case .supportive: "Gentle"
                            case .realistic: "Realistic"
                            case .challenging: "Tough"
                            }
                        }
                        Segmented(title: "Partner's voice", options: PracticeSetup.Persona.allCases, selection: $persona) {
                            $0 == .female ? "Female" : "Male"
                        }

                        if let confirmation {
                            HStack(alignment: .top, spacing: Space.md) {
                                GlassRowIcon(icon: "checkmark", color: Palette.sage)
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text("Here's the scene")
                                        .font(Typeface.label(15))
                                        .foregroundStyle(Palette.ink)
                                    Text(confirmation)
                                        .font(Typeface.body(15))
                                        .foregroundStyle(Palette.dim)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(Space.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassSurface(cornerRadius: Corner.lg)
                            .transition(.opacity)
                        }
                        if let problem {
                            Text(problem)
                                .font(Typeface.body(14))
                                .foregroundStyle(Palette.coralDeep)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaPadding(.top)
                .bottomEdgeFade()

                action
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.sm)
            }
        }
        .statusBarScrim()
        .toolbar(.hidden, for: .navigationBar)
        // A page with its own action at the bottom: the tab bar steps aside.
        .toolbar(.hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.25), value: confirmation)
        .onAppear { Analytics.enter("custom_situation") }
    }

    @ViewBuilder
    private var action: some View {
        if confirmation != nil {
            PrimaryButton(title: "Start speaking", systemImage: "mic.fill") {
                focus = nil
                Analytics.action("custom_situation")
                let situation = CustomSituation(description: trimmedDescription, partner: trimmedPartner, title: Self.title(for: trimmedPartner))
                onStart(situation, PracticeSetup(practice: situation.definition, pressure: pressure, persona: persona, situation: trimmedDescription))
            }
        } else {
            PrimaryButton(title: "Set the scene", isLoading: checking) { Task { await check() } }
                .disabled(!isComplete)
        }
    }

    /// The server restates the situation in one friendly line, or explains
    /// why it can't be rehearsed as written.
    private func check() async {
        focus = nil
        checking = true
        problem = nil
        defer { checking = false }
        do {
            let result = try await CustomSituationAPI.evaluate("\(trimmedDescription) (I'll be talking to \(trimmedPartner).)", language: language)
            if result.isAppropriate {
                confirmation = result.message
                Haptics.success()
            } else {
                problem = result.message
                Haptics.error()
            }
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "That didn't work. Please try again."
        }
    }

    static func title(for partner: String) -> String {
        let lowered = partner.prefix(1).lowercased() + partner.dropFirst()
        return "Talking to \(lowered)"
    }

    /// One question of the card: asked small and grey, answered below it.
    private func question<Content: View>(_ label: String, focus field: Field, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label)
                .font(Typeface.label(13))
                .foregroundStyle(Palette.muted)
            content()
                .font(Typeface.body(16))
                .foregroundStyle(Palette.ink)
                .tint(Palette.coral)
        }
        .padding(.vertical, Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { focus = field }
    }
}

/// Glass input with a coral focus ring.
struct InputChrome: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .font(Typeface.body(17))
            .foregroundStyle(Palette.ink)
            .tint(Palette.coral)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md + 2)
            .frame(minHeight: 54)
            .glassSurface(cornerRadius: Corner.md, interactive: true)
            .overlay {
                RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                    .strokeBorder(Palette.coral.opacity(focused ? 0.7 : 0), lineWidth: 1.5)
            }
            .animation(.easeOut(duration: 0.2), value: focused)
    }
}
