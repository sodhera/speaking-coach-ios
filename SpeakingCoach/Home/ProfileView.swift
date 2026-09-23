import SwiftUI

/// **Profile — everything about you.** A one-line header (hero title left,
/// Settings gear right), a summary band with one hero numeral, then the
/// record. No name here — Home already greets you by it — and deliberately
/// light on section labels.
struct ProfileView: View {
    let model: AppModel
    var onOpenReport: (PracticeReport) -> Void = { _ in }

    @State private var showsSettings = false
    @State private var opening: UUID?
    @State private var openError: String?

    private var history: PracticeHistory { model.history }

    var body: some View {
        NavigationStack {
            SceneScreen {
                HStack(alignment: .center) {
                    Text("Profile")
                        .font(Typeface.hero(28))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    GlassIconButton(systemImage: "gearshape", size: 56, iconSize: 20, color: Palette.dim, accessibilityLabel: "Settings") {
                        showsSettings = true
                    }
                }

                summaryBand
                    .padding(.top, Space.xxl)

                if let profile = model.profile, profile.moment != nil {
                    patternCard(profile)
                        .padding(.top, Space.xxl)
                }

                record
                    .padding(.top, Space.xxxl)
            }
            .refreshable {
                if let id = model.userID { await history.load(userID: id) }
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(model: model)
                .presentationDragIndicator(.visible)
        }
        .onAppear { Analytics.enter("profile") }
    }

    /// One read of the record: how much you've practised lately.
    private var summaryBand: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Rehearsals · last 7 days")
                .font(Typeface.label(13))
                .foregroundStyle(Palette.muted)
            Text("\(history.lastSevenDays)")
                .font(Typeface.hero(56))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: Double(history.lastSevenDays)))
            if let readiness = model.profile?.readiness, let after = model.profile?.planReadiness {
                Text("Readiness \(readiness)/10 when you started · \(after)/10 after your plan")
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.dim)
            } else if let readiness = model.profile?.readiness {
                Text("You started at \(readiness)/10 readiness")
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.dim)
            }
        }
    }

    private func patternCard(_ profile: CoachProfile) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            GlassRowIcon(icon: "sparkles")
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.pattern.name)
                    .font(Typeface.label(17))
                    .foregroundStyle(Palette.ink)
                Text(profile.pattern.fix)
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.lg)
        .glassSurface(cornerRadius: Corner.lg)
    }

    @ViewBuilder
    private var record: some View {
        if !history.records.isEmpty {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("Recent rehearsals")
                    .font(Typeface.title(20))
                    .foregroundStyle(Palette.ink)
                GlassRowGroup {
                    ForEach(Array(history.records.prefix(20).enumerated()), id: \.element.id) { index, record in
                        if index > 0 { GlassRowDivider() }
                        Button {
                            Haptics.heavy()
                            open(record)
                        } label: {
                            HStack(spacing: Space.md) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: Space.sm) {
                                        Text(record.title).font(Typeface.label(16)).foregroundStyle(Palette.ink).lineLimit(1)
                                        if record.parentID != nil {
                                            Text("RETRY")
                                                .font(Typeface.label(10))
                                                .tracking(0.6)
                                                .foregroundStyle(Palette.coralDeep)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Palette.coral.opacity(0.12)))
                                        }
                                    }
                                    Text(record.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                        .font(Typeface.body(13)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                if opening == record.id {
                                    ProgressView().tint(Palette.coral)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Palette.faint)
                                }
                            }
                            .padding(.vertical, Space.md)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(opening != nil)
                    }
                }
                if let openError {
                    Text(openError).font(Typeface.body(14)).foregroundStyle(Palette.danger)
                }
            }
        } else if history.loaded {
            Text("Your rehearsals will show up here.")
                .font(Typeface.body(15))
                .foregroundStyle(Palette.muted)
        }
    }

    private func open(_ record: PracticeRecord) {
        opening = record.id
        openError = nil
        Task {
            do {
                onOpenReport(try await history.report(id: record.id))
            } catch {
                openError = "That rehearsal couldn't be opened. Check your connection and try again."
            }
            opening = nil
        }
    }
}
