import SwiftUI
import UniformTypeIdentifiers

/// Presentations: your own slides, rehearsed out loud, then the audience's
/// questions. Decks stay on this phone.
struct PresentationsView: View {
    let store: PresentationStore
    let onBack: () -> Void

    @State private var importing = false
    @State private var working = false
    @State private var problem: String?
    @State private var selected: UUID?

    var body: some View {
        ZStack {
            MorningStage(depth: 0.3)
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        SubpageHeader(
                            title: String(localized: "Presentations", bundle: AppLanguage.bundle),
                            subtitle: String(localized: "Practice your talk with your own slides, then answer the questions your audience would ask.", bundle: AppLanguage.bundle),
                            onBack: onBack
                        )
                        if store.decks.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: Space.md) {
                                ForEach(store.decks) { deck in
                                    Button {
                                        Haptics.heavy()
                                        selected = deck.id
                                    } label: {
                                        DeckRow(store: store, deck: deck)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if let problem {
                            Text(problem)
                                .font(Typeface.body(14))
                                .foregroundStyle(Palette.coralDeep)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.xxl)
                }
                .safeAreaPadding(.top)
                .bottomEdgeFade()

                PrimaryButton(title: String(localized: "Add slides", bundle: AppLanguage.bundle), systemImage: "plus", isLoading: working) {
                    problem = nil
                    importing = true
                }
                .padding(.horizontal, Space.xxl)
                .padding(.bottom, Space.sm)
            }
        }
        .statusBarScrim()
        .toolbar(.hidden, for: .navigationBar)
        // A page with its own action at the bottom: the tab bar steps aside.
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selected) { id in
            if let deck = store.decks.first(where: { $0.id == id }) {
                DeckView(store: store, deck: deck, onBack: { selected = nil })
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.importTypes) { result in
            guard case .success(let url) = result else { return }
            Task { await add(url) }
        }
        .onAppear { Analytics.enter("presentations") }
    }

    static let importTypes: [UTType] = [.pdf] + [UTType(filenameExtension: "pptx")].compactMap { $0 }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: Space.md) {
                    Text("\(index + 1)")
                        .font(Typeface.label(14))
                        .foregroundStyle(Palette.coralDeep)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Palette.coral.opacity(0.12)))
                    Text(step)
                        .font(Typeface.body(16))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
            }
            Text("PDF works best. From PowerPoint or Keynote: File → Export → PDF.")
                .font(Typeface.body(13))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Corner.lg)
    }

    private static var steps: [String] { [
        String(localized: "Add your slides.", bundle: AppLanguage.bundle),
        String(localized: "Give the talk out loud, moving through them.", bundle: AppLanguage.bundle),
        String(localized: "Answer the questions your audience asks.", bundle: AppLanguage.bundle),
    ] }

    private func add(_ url: URL) async {
        working = true
        defer { working = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            var data = try Data(contentsOf: url)
            var name = url.lastPathComponent
            if url.pathExtension.lowercased() == "pptx" {
                data = try await PresentationAPI.convert(pptx: data, fileName: name)
                name = (name as NSString).deletingPathExtension + ".pdf"
            }
            let deck = try store.importPDF(data, fileName: name)
            Haptics.success()
            Analytics.action("presentation_added")
            Analytics.capture("presentation_added", ["slides": deck.slideCount, "from_pptx": url.pathExtension.lowercased() == "pptx"])
            selected = deck.id
        } catch {
            Haptics.error()
            problem = (error as? LocalizedError)?.errorDescription ?? String(localized: "That file couldn't be added. Try a PDF.", bundle: AppLanguage.bundle)
        }
    }
}

private struct DeckRow: View {
    let store: PresentationStore
    let deck: PresentationDeck

    var body: some View {
        HStack(spacing: Space.lg) {
            SlideImage(store: store, deck: deck.id, slide: 0, width: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.title)
                    .font(Typeface.label(16))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text(detail)
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.faint)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .glassSurface(cornerRadius: Corner.lg)
    }

    private var detail: String {
        PresentationDeck.summary(slides: deck.slideCount, practiced: store.rehearsals[deck.id]?.count ?? 0)
    }
}

/// A slide, rendered from the PDF off the main path and cached.
struct SlideImage: View {
    let store: PresentationStore
    let deck: UUID
    let slide: Int
    let width: CGFloat
    var cornerRadius: CGFloat = 8

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Rectangle().fill(Color.white.opacity(0.6)).aspectRatio(16 / 9, contentMode: .fit)
            }
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Palette.border, lineWidth: 1)
        }
        .shadow(color: Palette.ink.opacity(0.08), radius: 8, y: 3)
        .task(id: "\(deck)-\(slide)-\(Int(width))") {
            image = store.image(deck: deck, slide: slide, width: width)
        }
        .accessibilityLabel("Slide \(slide + 1)")
    }
}
