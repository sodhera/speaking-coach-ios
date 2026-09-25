import SwiftUI

/// Practice routine: a thirty-second prompt, with a reminder at the time and
/// on the days you choose.
struct RoutineView: View {
    let routine: RoutineStore
    let onBack: () -> Void

    @State private var draft = RoutineStore.Settings()
    @State private var trying = false
    @State private var notice: String?
    @State private var loaded = false

    var body: some View {
        ZStack {
            MorningStage(depth: 0.3)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    SubpageHeader(
                        title: String(localized: "Practice routine", bundle: AppLanguage.bundle),
                        subtitle: String(localized: "Thirty seconds of speaking a day, with a reminder when it's time.", bundle: AppLanguage.bundle),
                        onBack: onBack
                    )
                    promptSection
                    if let notice {
                        Text(notice)
                            .font(Typeface.body(14))
                            .foregroundStyle(Palette.coralDeep)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    SecondaryButton(title: String(localized: "Try today's prompt", bundle: AppLanguage.bundle), systemImage: "mic.fill") { trying = true }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.xxl)
                .padding(.bottom, Space.huge)
            }
            .safeAreaPadding(.top)
        }
        .statusBarScrim()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if !loaded {
                draft = routine.settings
                loaded = true
            }
            Analytics.enter("routine")
        }
        .fullScreenCover(isPresented: $trying) {
            PromptView(routine: routine, source: .practice) { trying = false }
        }
    }


    // MARK: Daily prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionTitle(text: String(localized: "Daily prompt", bundle: AppLanguage.bundle))
            GlassRowGroup {
                Toggle(isOn: Binding(get: { routine.settings.promptEnabled }, set: { on in savePrompt(enabled: on) })) {
                    rowLabel(String(localized: "Remind me", bundle: AppLanguage.bundle), icon: "bell")
                }
                .tint(Palette.coral)
                .frame(minHeight: 56)
                GlassRowDivider()
                timeRow(String(localized: "At", bundle: AppLanguage.bundle), minutes: $draft.promptMinutes)
                GlassRowDivider()
                DayPicker(days: $draft.promptDays)
                    .padding(.vertical, Space.md)
            }
        }
        .onChange(of: draft.promptMinutes) { _, _ in if routine.settings.promptEnabled { savePrompt(enabled: true) } }
        .onChange(of: draft.promptDays) { _, _ in if routine.settings.promptEnabled { savePrompt(enabled: true) } }
    }

    private func savePrompt(enabled: Bool) {
        Task {
            let ok = await routine.setPrompt(enabled: enabled && !draft.promptDays.isEmpty, minutes: draft.promptMinutes, days: draft.promptDays)
            notice = ok ? nil : String(localized: "Notifications are off for Speaking Coach. Turn them on in Settings for the daily prompt.", bundle: AppLanguage.bundle)
        }
    }

    // MARK: Pieces

    private func rowLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: Space.md) {
            GlassRowIcon(icon: icon)
            Text(title).font(Typeface.body(16)).foregroundStyle(Palette.ink)
        }
    }

    private func timeRow(_ title: String, minutes: Binding<Int>) -> some View {
        DatePicker(selection: Binding(
            get: { Calendar.current.date(from: DateComponents(hour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60)) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        ), displayedComponents: .hourAndMinute) {
            Text(title).font(Typeface.body(16)).foregroundStyle(Palette.ink)
        }
        .tint(Palette.coral)
        .frame(minHeight: 52)
    }
}

/// Seven round day toggles, Sunday first like the calendar.
struct DayPicker: View {
    @Binding var days: [Int]

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = AppLanguage.locale
        return calendar
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(1...7, id: \.self) { day in
                let isOn = days.contains(day)
                Button {
                    Haptics.selection()
                    if isOn { days.removeAll { $0 == day } } else { days = (days + [day]).sorted() }
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[day - 1])
                        .font(Typeface.label(14))
                        .foregroundStyle(isOn ? .white : Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Circle().fill(isOn ? Palette.coral : Palette.coral.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
