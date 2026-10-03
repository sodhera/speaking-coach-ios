import PhotosUI
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
    /// Interviews only: the CV, job post and notes the interviewer reads.
    /// Never sent to the practice server; only the voice partner sees them.
    var documents: [InterviewDocument] = []

    var id: String { practice.id }
}

/// The moment before a session, laid out like a track's page: its cover,
/// the title and goal, then the setup as a short list. The knobs are the
/// list's last row, only if you want them. One button starts it.
struct BriefingView: View {
    let practice: PracticeDefinition
    /// The account's CV, job post and notes; offered on interviews only.
    var documents: InterviewDocumentStore?
    let onBack: () -> Void
    let onStart: (PracticeSetup) -> Void

    @State private var setup: PracticeSetup
    @State private var adjusting = false
    @FocusState private var situationFocused: Bool
    @State private var importing = false
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var documentProblem: String?

    init(practice: PracticeDefinition, documents: InterviewDocumentStore? = nil, onBack: @escaping () -> Void, onStart: @escaping (PracticeSetup) -> Void) {
        self.practice = practice
        self.documents = documents
        self.onBack = onBack
        self.onStart = onStart
        // The first gentle practice never pressures; everything else starts realistic.
        let pressure: PracticeSetup.Pressure = practice.format == "guided" ? .supportive : .realistic
        _setup = State(initialValue: PracticeSetup(practice: practice, pressure: pressure, persona: .female))
    }

    var body: some View {
        ZStack {
            MorningStage(depth: 0.4)
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

                        if practice.category == "interviews", let documents {
                            documentsSection(documents)
                                .padding(.top, Space.xxl)
                        }
                    }
                    .padding(.horizontal, Space.xxl)
                    .padding(.top, Space.lg)
                    .padding(.bottom, Space.xl)
                }
                .scrollDismissesKeyboard(.interactively)

                PrimaryButton(title: String(localized: "Start speaking", bundle: AppLanguage.bundle), systemImage: "mic.fill") {
                    situationFocused = false
                    Analytics.action("briefing")
                    var final = setup
                    final.situation = setup.situation.trimmingCharacters(in: .whitespacesAndNewlines)
                    if practice.category == "interviews" { final.documents = documents?.documents ?? [] }
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
        .fileImporter(isPresented: $importing, allowedContentTypes: DocumentText.fileTypes) { result in
            guard case .success(let url) = result else { return }
            addDocument(named: url.lastPathComponent) { try await DocumentText.read(url) }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            addDocument(named: String(localized: "Photo", bundle: AppLanguage.bundle)) {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw DocumentText.Failure.noText }
                return try await DocumentText.read(image: data)
            }
        }
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
            detailRow(String(localized: "Partner", bundle: AppLanguage.bundle), practice.partner)
            GlassRowDivider()
            detailRow(String(localized: "Length", bundle: AppLanguage.bundle), String(localized: "\(practice.durationMinutes) min", bundle: AppLanguage.bundle))
            GlassRowDivider()
            detailRow(String(localized: "Pressure", bundle: AppLanguage.bundle), pressureName(setup.pressure))
            let situation = setup.situation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !situation.isEmpty {
                GlassRowDivider()
                detailRow(String(localized: "Your situation", bundle: AppLanguage.bundle), situation)
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

    // MARK: Documents

    /// The CV, the job post and notes, read on the phone. The interviewer
    /// gets their text, so the questions are about this person and this role.
    private func documentsSection(_ store: InterviewDocumentStore) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionTitle(text: String(localized: "Your CV and the job", bundle: AppLanguage.bundle))
            Text("Add your CV, the job post or your notes. After you allow AI data sharing and start an interview, their text is sent to ElevenLabs so your interviewer can ask about your experience. Remove anything you do not want to share.")
                .font(Typeface.body(15))
                .foregroundStyle(Palette.dim)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if !store.documents.isEmpty {
                GlassRowGroup {
                    ForEach(Array(store.documents.enumerated()), id: \.element.id) { index, document in
                        if index > 0 { GlassRowDivider() }
                        HStack(spacing: Space.md) {
                            GlassRowIcon(icon: "doc.text")
                            Text(document.name)
                                .font(Typeface.body(16))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: Space.sm)
                            Button {
                                Haptics.selection()
                                store.remove(document)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Palette.muted)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Remove \(document.name)", bundle: AppLanguage.bundle))
                        }
                        .frame(minHeight: 52)
                    }
                }
            }

            if reading {
                HStack(spacing: 0) {
                    Text("Reading the text")
                    WaitingDots(font: Typeface.body(15), color: Palette.dim)
                }
                .font(Typeface.body(15))
                .foregroundStyle(Palette.dim)
                .frame(maxWidth: .infinity, minHeight: 50)
            } else if !store.isFull {
                GlassGroup(spacing: Space.md) {
                    HStack(spacing: Space.md) {
                        Button {
                            Haptics.heavy()
                            documentProblem = nil
                            importing = true
                        } label: {
                            DocumentButtonLabel(title: String(localized: "Add a file", bundle: AppLanguage.bundle), systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.plain)
                        .glassSurface(cornerRadius: 999, interactive: true)
                        PhotosPicker(selection: $photo, matching: .images) {
                            DocumentButtonLabel(title: String(localized: "Add a photo", bundle: AppLanguage.bundle), systemImage: "photo")
                        }
                        .buttonStyle(.plain)
                        .glassSurface(cornerRadius: 999, interactive: true)
                    }
                }
            }

            if let documentProblem {
                Text(documentProblem)
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("They stay on this phone. Only their text goes to your partner, in your interview sessions.")
                .font(Typeface.body(13))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addDocument(named name: String, read: @escaping () async throws -> String) {
        guard let documents else { return }
        documentProblem = nil
        reading = true
        Task {
            defer { reading = false }
            do {
                let text = try await read()
                documents.add(name: name, text: text)
                Haptics.success()
                Analytics.action("briefing_document")
            } catch {
                Haptics.error()
                documentProblem = (error as? LocalizedError)?.errorDescription ?? DocumentText.Failure.noText.localizedDescription
            }
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
        case .supportive: String(localized: "Gentle", bundle: AppLanguage.bundle)
        case .realistic: String(localized: "Realistic", bundle: AppLanguage.bundle)
        case .challenging: String(localized: "Tough", bundle: AppLanguage.bundle)
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
            Segmented(title: String(localized: "Pressure", bundle: AppLanguage.bundle), options: PracticeSetup.Pressure.allCases, selection: $setup.pressure, label: pressureName)
            Segmented(title: String(localized: "Pace", bundle: AppLanguage.bundle), options: PracticeSetup.Pacing.allCases, selection: $setup.pacing) {
                $0 == .patient ? String(localized: "Time to think", bundle: AppLanguage.bundle) : String(localized: "Natural", bundle: AppLanguage.bundle)
            }
            Segmented(title: String(localized: "Partner's voice", bundle: AppLanguage.bundle), options: PracticeSetup.Persona.allCases, selection: $setup.persona) {
                $0 == .female ? String(localized: "Female", bundle: AppLanguage.bundle) : String(localized: "Male", bundle: AppLanguage.bundle)
            }
        }
    }
}

/// The document actions' label: the room's paired glass pills.
private struct DocumentButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(Typeface.label(15))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Capsule())
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
