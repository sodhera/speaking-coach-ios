import SwiftUI

/// **What you've done**, as Profile shows it under your name: every
/// session, newest first, each reopening its feedback. Retries sit under
/// the session they went back to. The week and the streak live at the top
/// of Practice, where they ask for today.
///
/// Honest by construction: every count is a saved report.
struct ActivitySections: View {
    let model: AppModel
    var onOpenReport: (PracticeReport) -> Void = { _ in }

    @State private var opening: UUID?
    @State private var openError: String?
    @State private var showsAll = false

    /// Sessions listed before "Show more".
    private static let shownAtFirst = 8

    private var history: PracticeHistory { model.history }
    private var entries: [RehearsalEntry] { RehearsalEntry.entries(from: history.records) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(text: "History")
            historyList
                .padding(.top, Space.md)
        }
    }

    // MARK: History

    @ViewBuilder
    private var historyList: some View {
        let entries = entries
        if entries.isEmpty {
            EmptyHistory(loaded: history.loaded)
        } else {
            let shown = showsAll ? entries : Array(entries.prefix(Self.shownAtFirst))
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { GlassRowDivider() }
                    VStack(alignment: .leading, spacing: 0) {
                        sessionRow(entry.record)
                        ForEach(entry.retries) { retryRow($0) }
                    }
                }
            }
            .padding(.horizontal, Space.lg)
            .glassSurface(cornerRadius: Corner.lg)

            if entries.count > Self.shownAtFirst {
                QuietButton(title: showsAll ? "Show fewer" : "Show \(entries.count - Self.shownAtFirst) more", color: Palette.coralDeep) {
                    withAnimation(.easeInOut(duration: 0.3)) { showsAll.toggle() }
                }
            }
        }
        if let openError {
            Text(openError)
                .font(Typeface.body(14))
                .foregroundStyle(Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.sm)
        }
    }

    private func sessionRow(_ record: PracticeRecord) -> some View {
        Button { open(record) } label: {
            HStack(spacing: Space.md) {
                GlassRowIcon(icon: record.parentID == nil ? SessionText.icon(for: record) : "arrow.counterclockwise")
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(Typeface.label(16))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    // A retry whose session is too old to be listed stands
                    // alone, so it says what it is.
                    Text(SessionText.when(record.date) + (record.parentID == nil ? "" : " · Retry"))
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.sm)
                trailing(for: record)
            }
            .padding(.vertical, Space.md)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(opening != nil)
    }

    /// A retry reads as a footnote to its session, indented under the title.
    private func retryRow(_ retry: PracticeRecord) -> some View {
        Button { open(retry) } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.coralDeep)
                Text("Retry")
                    .font(Typeface.label(14))
                    .foregroundStyle(Palette.ink)
                Text(SessionText.when(retry.date))
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                Spacer(minLength: Space.sm)
                trailing(for: retry)
            }
            .padding(.leading, GlassRowIcon.width + Space.md)
            .padding(.bottom, Space.md)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(opening != nil)
    }

    @ViewBuilder
    private func trailing(for record: PracticeRecord) -> some View {
        if opening == record.id {
            ProgressView().tint(Palette.coral).controlSize(.small)
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.faint)
        }
    }

    private func open(_ record: PracticeRecord) {
        Haptics.heavy()
        opening = record.id
        openError = nil
        Task {
            do { onOpenReport(try await history.report(id: record.id)) }
            catch { openError = "That session couldn't be opened. Check your connection and try again." }
            opening = nil
        }
    }
}

// MARK: - Formatting

/// How a session is named and dated wherever it's listed.
enum SessionText {
    /// The same glyph as the record's situation card on Home.
    static func icon(for record: PracticeRecord) -> String {
        if let id = record.activityID, let practice = PracticeCatalog.definition(id),
           let section = HomeSection.containing(practice) {
            return section.icon
        }
        if record.title == CustomSituation.ieltsSpeaking.title { return HomeSection.ielts.icon }
        if record.title == CustomSituation.streetHello.title || record.isCustom { return HomeSection.custom.icon }
        return "text.bubble"
    }

    /// "Today, 10:43 AM", "Yesterday, 6:10 PM", "Monday, 9:05 AM", then
    /// "Tue, Sep 8" once it's more than a week back.
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Today, \(time)" }
        let daysBack = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if daysBack == 1 { return "Yesterday, \(time)" }
        if daysBack < 7 { return "\(date.formatted(.dateTime.weekday(.wide))), \(time)" }
        return calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// A day for mid-sentence: "today", "yesterday", "on Monday", "on Sep 8".
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let daysBack = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch daysBack {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2..<7: return "on \(date.formatted(.dateTime.weekday(.wide)))"
        default: return "on \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }
}

// MARK: - Models

/// The last few calendar weeks, a row per week, with today in the last row.
struct PracticeWeeks: Equatable {
    struct Day: Equatable {
        let date: Date
        let number: Int
        /// Sessions and retries saved that day.
        let count: Int
        let isToday: Bool
        let isFuture: Bool
    }

    let rows: [[Day]]

    init(records: [PracticeRecord], weeks: Int = 5, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let first = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek
        let counts = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }.mapValues(\.count)
        rows = (0..<weeks).map { week in
            (0..<7).map { weekday in
                let date = calendar.date(byAdding: .day, value: week * 7 + weekday, to: first) ?? first
                return Day(
                    date: date,
                    number: calendar.component(.day, from: date),
                    count: counts[date] ?? 0,
                    isToday: date == today,
                    isFuture: date > today
                )
            }
        }
    }

    /// Sessions this calendar week: the last row.
    var thisWeek: Int { rows.last?.reduce(0) { $0 + $1.count } ?? 0 }

    var daysPractised: Int { rows.joined().filter { $0.count > 0 }.count }
}

/// A session and the retries that went back to it. Ordered by the latest
/// of them, so a retry done today brings its session to the top.
struct RehearsalEntry: Identifiable, Equatable {
    let record: PracticeRecord
    let retries: [PracticeRecord]

    var id: UUID { record.id }

    var latest: Date { retries.map(\.date).reduce(record.date, max) }

    static func entries(from records: [PracticeRecord]) -> [RehearsalEntry] {
        let ids = Set(records.map(\.id))
        let retries = Dictionary(grouping: records.filter { $0.parentID.map(ids.contains) ?? false }) { $0.parentID! }
        return records
            .filter { record in record.parentID.map { !ids.contains($0) } ?? true }
            .map { RehearsalEntry(record: $0, retries: (retries[$0.id] ?? []).sorted { $0.date < $1.date }) }
            .sorted { $0.latest > $1.latest }
    }
}

// MARK: - Empty

/// No ghost rows or sample numbers: an empty history says so, warmly.
private struct EmptyHistory: View {
    let loaded: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            GlassRowIcon(icon: "mic")
            VStack(alignment: .leading, spacing: 3) {
                Text(loaded ? "Nothing here yet" : "Loading your history…")
                    .font(Typeface.label(16))
                    .foregroundStyle(Palette.ink)
                if loaded {
                    Text("Your first session shows up here, with its feedback a tap away.")
                        .font(Typeface.body(14))
                        .foregroundStyle(Palette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Corner.lg)
    }
}
