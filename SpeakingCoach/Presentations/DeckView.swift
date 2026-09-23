import SwiftUI

/// One deck: its slides, who it's for, and every time you've rehearsed it.
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
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Space.xxl) {
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

                        TextField("", text: $title, prompt: Text("Presentation title"), axis: .vertical)
                            .font(Typeface.hero(28))
                            .foregroundStyle(Palette.ink)
                            .tint(Palette.coral)
                            .focused($focus, equals: .title)
                            .submitLabel(.done)

                        slides

                        VStack(alignment: .leading, spacing: Space.lg) {
                            Kicker(text: "Your audience")
                            field("Who's listening?", text: $brief.audience, prompt: "e.g. the leadership team", focus: .audience)
                            field("What should they do after?", text: $brief.purpose, prompt: "e.g. approve the budget for Q3", focus: .purpose)
                            field("Anything they'd push on? (optional)", text: $brief.instructions, prompt: "e.g. they worry about timelines", focus: .instructions, multiline: true)
                            Segmented(title: "How hard should they push?", options: PresentationBrief.QuestionStyle.allCases, selection: $brief.questionStyle) {
                                switch $0 {
                                case .supportive: "Gently"
                                case .curious: "Curious"
                                case .challenging: "Tough"
                                }
                            }
                        }

                        if !rehearsals.isEmpty {
                            VStack(alignment: .leading, spacing: Space.md) {
                                Kicker(text: "Rehearsals")
                                GlassRowGroup {
                                    ForEach(Array(rehearsals.enumerated()), id: \.element.id) { index, rehearsal in
                                        if index > 0 { GlassRowDivider() }
                                        Button {
                                            Haptics.heavy()
                                            reviewing = rehearsal
                                        } label: {
                                            GlassRow(
                                                icon: "waveform",
                                                title: rehearsal.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
                                                value: Self.duration(rehearsal.durationMs),
                                                showsChevron: true
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.huge)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaPadding(.top)
                .bottomEdgeFade()

                PrimaryButton(title: rehearsals.isEmpty ? "Rehearse it" : "Rehearse again", systemImage: "mic.fill") {
                    focus = nil
                    save()
                    rehearsing = true
                }
                .padding(.horizontal, Space.xxl)
                .padding(.bottom, Space.sm)
            }
        }
        .statusBarScrim()
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { save(); onBack() }
        .onDisappear(perform: save)
        .fullScreenCover(isPresented: $rehearsing) {
            RehearsalView(store: store, deck: current, language: language) { rehearsing = false }
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
            Text("Its slides and every rehearsal recording will be removed from this phone.")
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

    private func field(_ label: String, text: Binding<String>, prompt: String, focus field: Field, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(label).font(Typeface.label(14)).foregroundStyle(Palette.dim)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Palette.muted), axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 2...5 : 1...1)
                .focused($focus, equals: field)
                .modifier(InputChrome(focused: focus == field))
        }
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
