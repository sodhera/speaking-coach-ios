import SwiftUI

/// Activity and past feedback in one place. A readiness rating is shown as
/// the user's own check-in, separate from completed rehearsal counts.
struct ProgressScreen: View {
    let model: AppModel
    var onOpenReport: (PracticeReport) -> Void = { _ in }

    @State private var opening: UUID?
    @State private var openError: String?

    private var history: PracticeHistory { model.history }

    var body: some View {
        NavigationStack {
            SceneScreen {
                Text("Progress")
                    .font(Typeface.hero(30))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, Space.md)

                HStack(alignment: .top, spacing: Space.md) {
                    metric("This week", value: "\(history.lastSevenDays)", detail: "rehearsals")
                    metric("Current streak", value: "\(history.streak)", detail: "days")
                }
                .padding(.top, Space.xl)

                if let readiness = model.profile?.readiness {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Kicker(text: "Your own check-in")
                        if let after = model.profile?.planReadiness {
                            Text("Readiness: \(readiness)/10 when you started → \(after)/10 after your plan")
                        } else {
                            Text("Readiness when you started: \(readiness)/10")
                        }
                    }
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.dim)
                    .padding(.top, Space.xl)
                }

                VStack(alignment: .leading, spacing: Space.md) {
                    Text("Past rehearsals")
                        .font(Typeface.title(21))
                        .foregroundStyle(Palette.ink)
                    if history.records.isEmpty {
                        Text(history.loaded ? "Your feedback will appear here after your first rehearsal." : "Loading your rehearsals…")
                            .font(Typeface.body(15))
                            .foregroundStyle(Palette.dim)
                    } else {
                        GlassRowGroup {
                            ForEach(Array(history.records.prefix(30).enumerated()), id: \.element.id) { index, record in
                                if index > 0 { GlassRowDivider() }
                                Button { open(record) } label: {
                                    HStack(spacing: Space.md) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(record.title)
                                                .font(Typeface.label(16))
                                                .foregroundStyle(Palette.ink)
                                            Text(record.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                                 + (record.parentID == nil ? "" : " · Retry"))
                                                .font(Typeface.body(13))
                                                .foregroundStyle(Palette.muted)
                                        }
                                        Spacer(minLength: 8)
                                        if opening == record.id { ProgressView().tint(Palette.coral) }
                                        else { Image(systemName: "chevron.right").foregroundStyle(Palette.faint) }
                                    }
                                    .frame(minHeight: 60)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(opening != nil)
                            }
                        }
                    }
                    if let openError {
                        Text(openError).font(Typeface.body(14)).foregroundStyle(Palette.danger)
                    }
                }
                .padding(.top, Space.xxl)
            }
            .refreshable { if let id = model.userID { await history.load(userID: id) } }
        }
        .onAppear { Analytics.enter("progress") }
    }

    private func metric(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(Typeface.label(13)).foregroundStyle(Palette.dim)
            Text(value).font(Typeface.hero(32)).foregroundStyle(Palette.ink)
            Text(detail).font(Typeface.body(13)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .glassSurface(cornerRadius: Corner.lg)
    }

    private func open(_ record: PracticeRecord) {
        opening = record.id
        openError = nil
        Task {
            do { onOpenReport(try await history.report(id: record.id)) }
            catch { openError = "That rehearsal couldn't be opened. Check your connection and try again." }
            opening = nil
        }
    }
}
