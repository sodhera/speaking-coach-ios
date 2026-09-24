import SwiftUI

/// One deck, in the same language as the rest of the app: a quiet line of
/// facts over the title, the slides, the audience as one card, then every
/// session with it.
struct DeckView: View {
    let store: PresentationStore
    let deck: PresentationDeck
    let language: String
    let onBack: () -> Void

    @State private var title: String
    @State private var brief: PresentationBrief
    @State private var rehearsing = false
    @State private var reviewing: PresentationRehearsal?
    @State private var confirmingDelete = false
    @FocusState private var focus: Field?

    private enum Field { case title, audience, purpose, instructions }

    init(store: PresentationStore, deck: PresentationDeck, language: String, onBack: @escaping () -> Void) {
        self.store = store
        self.deck = deck
        self.language = language
        self.onBack = onBack
        _title = State(initialValue: deck.title)
        _brief = State(initialValue: deck.brief)
    }

    private var rehearsals: [PresentationRehearsal] { store.rehearsals[deck.id] ?? [] }

    /// The deck as edited here, so a rehearsal always sees the latest brief.
    private var current: PresentationDeck {
        var edited = store.decks.first { $0.id == deck.id } ?? deck
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.title = trimmed.isEmpty ? deck.title : trimmed
        edited.brief = brief
        return edited
    }

    var body: some View {
        ZStack {
            MorningStage(depth: 0.3, ripples: false)
            VStack(spacing: 0) {
                // Pinned, so the controls never slide under the status bar's fade.
                header
                    .padding(.horizontal, Space.xxl)
                    .padding(.top, Space.sm)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(summary)
                            .font(Typeface.label(14))
                            .foregroundStyle(Palette.muted)
                        TextField("", text: $title, prompt: Text("Presentation title"), axis: .vertical)
                            .font(Typeface.hero(28))
                            .foregroundStyle(Palette.ink)
                            .tint(Palette.coral)
                            .lineLimit(1...4)
                            .focused($focus, equals: .title)
                            .submitLabel(.done)
                            .padding(.top, Space.xs)

                        slides
                            .padding(.top, Space.lg)

                        SectionTitle(text: "Your audience")
                            .padding(.top, Space.xxl)
                        GlassRowGroup {
                            field("Who's listening?", text: $brief.audience, prompt: "e.g. the leadership team", focus: .audience)
                            GlassRowDivider()
                            field("What should they do after?", text: $brief.purpose, prompt: "e.g. approve the budget for Q3", focus: .purpose)
                            GlassRowDivider()
                            field("Anything they'd push on?", text: $brief.instructions, prompt: "Optional · e.g. they worry about timelines", focus: .instructions, multiline: true)
                        }
                        .padding(.top, Space.md)

                        Segmented(title: "How hard should they push?", options: PresentationBrief.QuestionStyle.allCases, selection: $brief.questionStyle) {
                            switch $0 {
                            case .supportive: "Gently"
                            case .curious: "Curious"
                            case .challenging: "Tough"
                            }
                        }
                        .padding(.top, Space.xl)

                        if !rehearsals.isEmpty {
                            SectionTitle(text: "Sessions")
                                .padding(.top, Space.xxl)
                            GlassRowGroup {
                                ForEach(Array(rehearsals.enumerated()), id: \.element.id) { index, rehearsal in
                                    if index > 0 { GlassRowDivider() }
                                    Button {
                                        Haptics.heavy()
                                        reviewing = rehearsal
                                    } label: {
                                        GlassRow(
                                            icon: "waveform",
                                            title: SessionText.when(rehearsal.startedAt),
                                            value: Self.duration(rehearsal.durationMs),
                                            showsChevron: true
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, Space.md)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xxl)
                    .padding(.top, Space.lg)
                    .padding(.bottom, Space.huge)
                }
                .scrollDismissesKeyboard(.interactively)
                .bottomEdgeFade()

                PrimaryButton(title: rehearsals.isEmpty ? "Practise it" : "Practise again", systemImage: "mic.fill") {
                    focus = nil
                    save()
                    rehearsing = true
                }
                .padding(.horizontal, Space.xxl)
                .padding(.bottom, Space.sm)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // A page with its own action at the bottom: the tab bar steps aside.
        .toolbar(.hidden, for: .tabBar)
        .onDisappear(perform: save)
        .fullScreenCover(isPresented: $rehearsing) {
            RehearsalView(
                store: store,
                deck: current,
                language: language,
                onClose: { rehearsing = false },
                demoRecording: LaunchFlags.has("-zara-demo")
            )
        }
        .navigationDestination(item: $reviewing) { rehearsal in
            RehearsalReviewView(store: store, deck: current, rehearsalID: rehearsal.id, language: language, onBack: { reviewing = nil })
        }
        .confirmationDialog("Delete this presentation?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(deck)
                onBack()
            }
        } message: {
            Text("Its slides and every session recording will be removed from this phone.")
        }
    }

    private var header: some View {
        HStack {
            GlassBackButton { save(); onBack() }
            Spacer()
            Menu {
                Button("Delete presentation", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .glassSurface(cornerRadius: 22, interactive: true)
            }
            .accessibilityLabel("More")
        }
    }

    /// "12 slides · Practised twice", quietly above the title.
    private var summary: String {
        let slides = deck.slideCount == 1 ? "1 slide" : "\(deck.slideCount) slides"
        switch rehearsals.count {
        case 0: return "\(slides) · Not practised yet"
        case 1: return "\(slides) · Practised once"
        case 2: return "\(slides) · Practised twice"
        default: return "\(slides) · Practised \(rehearsals.count) times"
        }
    }

    private var slides: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Space.md) {
                ForEach(0..<deck.slideCount, id: \.self) { index in
                    SlideImage(store: store, deck: deck.id, slide: index, width: 200)
                }
            }
            .padding(.horizontal, Space.xxl)
            .padding(.vertical, Space.md)
        }
        .padding(.horizontal, -Space.xxl)
        .frame(height: 150)
    }

    /// A question and its answer as one row of the audience card.
    private func field(_ label: String, text: Binding<String>, prompt: String, focus field: Field, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label)
                .font(Typeface.label(13))
                .foregroundStyle(Palette.muted)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Palette.faint), axis: multiline ? .vertical : .horizontal)
                .font(Typeface.body(16))
                .foregroundStyle(Palette.ink)
                .tint(Palette.coral)
                .lineLimit(multiline ? 1...5 : 1...1)
                .focused($focus, equals: field)
        }
        .padding(.vertical, Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { focus = field }
    }

    private func save() {
        guard store.decks.contains(where: { $0.id == deck.id }) else { return }
        let edited = current
        if edited.title != store.decks.first(where: { $0.id == deck.id })?.title || edited.brief != store.decks.first(where: { $0.id == deck.id })?.brief {
            store.update(edited)
        }
    }

    static func duration(_ ms: Int) -> String {
        let seconds = ms / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension PresentationRehearsal: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
