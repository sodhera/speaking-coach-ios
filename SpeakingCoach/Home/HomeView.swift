import SwiftUI

/// Two tabs, each with one job — the SleepBlock shell. The system tab bar
/// becomes Liquid Glass on iOS 26 by itself.
struct MainShellView: View {
    let model: AppModel
    let onStart: (PracticeSetup) -> Void
    var onOpenReport: (PracticeReport) -> Void = { _ in }

    var body: some View {
        TabView {
            HomeView(model: model, onStart: onStart)
                .tabItem { Label("Home", systemImage: "house.fill") }
            ProfileView(model: model, onOpenReport: onOpenReport)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Palette.coral)
    }
}

/// **Home — go rehearse.** A near-wordless instrument that never scrolls:
/// a small-caps greeting over the name, the bloom breathing at the centre as
/// the app's living state, the next rehearsal named in one glass capsule
/// beneath it, and one action where the thumb rests. Status sits at the
/// edges — the streak top-left, the full library top-right.
struct HomeView: View {
    let model: AppModel
    let onStart: (PracticeSetup) -> Void

    @State private var path: [PracticeDefinition] = []
    @State private var showsLibrary = false

    private var profile: CoachProfile? { model.profile }
    private var upNext: PracticeDefinition? {
        PracticeCatalog.definition(profile?.moment?.firstPracticeID ?? "interview_tell_me_about_yourself")
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                MorningStage(depth: 0.2)
                content
                    .padding(.horizontal, Space.xxl)
                    .safeAreaPadding(.top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PracticeDefinition.self) { practice in
                BriefingView(practice: practice, onBack: { path.removeLast() }, onStart: onStart)
            }
        }
        .sheet(isPresented: $showsLibrary) {
            LibraryView { setup in
                showsLibrary = false
                onStart(setup)
            }
            .presentationDragIndicator(.visible)
        }
        .onAppear { Analytics.enter("home") }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                VStack(spacing: Space.sm) {
                    Kicker(text: greeting)
                    Text(profile?.firstName.isEmpty == false ? profile!.firstName : "Welcome")
                        .font(Typeface.hero(36))
                        .foregroundStyle(Palette.ink)
                }
                .padding(.top, Space.huge)

                HStack {
                    StreakChip(count: model.history.streak)
                    Spacer()
                    GlassIconButton(systemImage: "square.grid.2x2", size: 44, iconSize: 16, accessibilityLabel: "All rehearsals") {
                        showsLibrary = true
                    }
                }
            }

            Spacer(minLength: Space.xxxl)

            VStack(spacing: Space.xxl) {
                BloomMark(size: 170)
                if let upNext {
                    Button {
                        Haptics.heavy()
                        path.append(upNext)
                    } label: {
                        HStack(spacing: Space.sm) {
                            Image(systemName: "mic.fill").foregroundStyle(Palette.coral)
                            Text(upNext.title).foregroundStyle(Palette.ink)
                            Text("· \(upNext.durationMinutes) min").foregroundStyle(Palette.muted)
                        }
                        .font(Typeface.label(15))
                        .padding(.horizontal, Space.xl)
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassSurface(cornerRadius: 999, interactive: true)
                    .accessibilityLabel("Up next: \(upNext.title), \(upNext.durationMinutes) minutes")
                }
            }

            Spacer(minLength: Space.xxxl)

            VStack(spacing: Space.lg) {
                PrimaryButton(title: "Start rehearsal", systemImage: "mic.fill") {
                    if let upNext { path.append(upNext) }
                }
                if let last = lastRehearsal {
                    Text(last)
                        .font(Typeface.body(14))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.bottom, Space.xxxl)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
    }

    /// Only when it can honestly be called recent — never a weeks-old date
    /// dressed up as "last".
    private var lastRehearsal: String? {
        guard let last = model.history.records.first,
              let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last.date), to: Calendar.current.startOfDay(for: .now)).day,
              days <= 6 else { return nil }
        let when = days == 0 ? "today" : days == 1 ? "yesterday" : "\(days) days ago"
        return "Last rehearsal \(when)"
    }
}

/// The streak at the top-left edge. It shows zero — a `0` where a number is
/// meant to grow is the invitation — but zero never *celebrates*: it wears
/// the hollow muted flame, and only a live streak earns the filled coral.
private struct StreakChip: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: count > 0 ? "flame.fill" : "flame")
                .foregroundStyle(count > 0 ? Palette.coral : Palette.muted)
            Text("\(count)")
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: Double(count)))
        }
        .font(Typeface.label(15))
        .padding(.horizontal, Space.md)
        .frame(minWidth: 44, minHeight: 44)
        .glassSurface(cornerRadius: 999)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count)-day streak")
    }
}

// MARK: - Library

/// Every rehearsal, grouped, one tap from its briefing.
struct LibraryView: View {
    let onStart: (PracticeSetup) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: [PracticeDefinition] = []

    var body: some View {
        NavigationStack(path: $path) {
            SceneScreen(depth: 0.2) {
                HStack(alignment: .center) {
                    Text("All rehearsals")
                        .font(Typeface.hero(28))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    GlassIconButton(systemImage: "xmark", size: 40, iconSize: 14, color: Palette.dim, accessibilityLabel: "Close") { dismiss() }
                }
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xxl)

                VStack(alignment: .leading, spacing: Space.xxl) {
                    ForEach(PracticeCategory.allCases) { category in
                        let items = PracticeCatalog.all.filter { $0.category == category.rawValue }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: Space.md) {
                                Kicker(text: category.title)
                                GlassRowGroup {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { index, practice in
                                        if index > 0 { GlassRowDivider() }
                                        Button {
                                            Haptics.heavy()
                                            path.append(practice)
                                        } label: {
                                            HStack(spacing: Space.md) {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(practice.title).font(Typeface.label(16)).foregroundStyle(Palette.ink)
                                                    Text("\(practice.partner) · \(practice.durationMinutes) min")
                                                        .font(Typeface.body(13)).foregroundStyle(Palette.muted)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.faint)
                                            }
                                            .padding(.vertical, Space.md)
                                            .frame(minHeight: 60)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: PracticeDefinition.self) { practice in
                BriefingView(practice: practice, onBack: { path.removeLast() }, onStart: onStart)
            }
        }
    }
}

// MARK: - Categories

enum PracticeCategory: String, CaseIterable, Identifiable {
    case interviews, work, difficult, big_moments, social

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interviews: "Interviews"
        case .work: "Work"
        case .difficult: "Difficult conversations"
        case .big_moments: "Big moments"
        case .social: "Social"
        }
    }

    /// The user's own kind of moment leads the list.
    static func ordered(firstFor moment: SpeakingMoment?) -> [PracticeCategory] {
        let lead: PracticeCategory? = switch moment {
        case .interview: .interviews
        case .raise, .speakingUp: .work
        case .hardConversation: .difficult
        case .presentation: .big_moments
        case .meetingPeople, .everyday: .social
        case nil: nil
        }
        guard let lead else { return allCases }
        return [lead] + allCases.filter { $0 != lead }
    }
}
