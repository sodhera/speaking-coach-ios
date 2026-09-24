import FamilyControls
import SwiftUI

/// Practice routine: a thirty-second prompt on the days you choose, and
/// "speak to unlock" — the apps you pick stay shielded during a window
/// until you've said one thing out loud.
struct RoutineView: View {
    let routine: RoutineStore
    let language: String
    let onBack: () -> Void

    @State private var draft = RoutineStore.Settings()
    @State private var picking = false
    @State private var pickerSelection = FamilyActivitySelection()
    @State private var trying = false
    @State private var notice: String?
    @State private var loaded = false

    var body: some View {
        ZStack {
            MorningStage(depth: 0.3, ripples: false)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    SubpageHeader(
                        title: "Practice routine",
                        subtitle: "Thirty seconds of speaking a day, and your distracting apps held until you've spoken.",
                        onBack: onBack
                    )
                    unlockSection
                    promptSection
                    if let notice {
                        Text(notice)
                            .font(Typeface.body(14))
                            .foregroundStyle(Palette.coralDeep)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    SecondaryButton(title: "Try today's prompt", systemImage: "mic.fill") { trying = true }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.xxl)
                .padding(.bottom, Space.huge)
            }
            .safeAreaPadding(.top)
        }
        .statusBarScrim()
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack(onBack)
        .onAppear {
            routine.reconcile()
            if !loaded {
                draft = routine.settings
                pickerSelection = routine.selection
                loaded = true
            }
            Analytics.enter("routine")
        }
        .familyActivityPicker(isPresented: $picking, selection: $pickerSelection)
        .onChange(of: pickerSelection) { _, selection in
            routine.setSelection(selection)
            applyUnlockIfOn()
        }
        .fullScreenCover(isPresented: $trying) {
            PromptView(routine: routine, source: .practice, language: language) { trying = false }
        }
    }

    // MARK: Speak to unlock

    private var unlockSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionTitle(text: "Speak to unlock")
            if !routine.isSupported {
                note("Speak to unlock uses Screen Time, so it's set up on your iPhone.")
            } else if routine.authorization != .approved {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text("Choose apps that pull you away. During your window they stay shut until you say one thing out loud.")
                        .font(Typeface.body(15))
                        .foregroundStyle(Palette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Apple's Screen Time keeps your choices private — Speaking Coach never sees which apps they are.")
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "Allow Screen Time", systemImage: "hourglass") {
                        Task {
                            do {
                                try await routine.requestAuthorization()
                                if routine.authorization == .approved { picking = true }
                            } catch {
                                notice = "Screen Time access wasn't allowed. You can try again any time."
                            }
                        }
                    }
                }
                .padding(Space.xl)
                .glassSurface(cornerRadius: Corner.lg)
            } else {
                GlassRowGroup {
                    Toggle(isOn: Binding(get: { routine.settings.unlockEnabled }, set: setUnlock)) {
                        rowLabel("Speak to unlock", icon: "lock.open.fill")
                    }
                    .tint(Palette.coral)
                    .frame(minHeight: 56)
                    GlassRowDivider()
                    Button {
                        Haptics.heavy()
                        picking = true
                    } label: {
                        GlassRow(icon: "square.grid.2x2.fill", title: "Apps", value: routine.selectionCount == 0 ? "Choose" : "\(routine.selectionCount) chosen", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    GlassRowDivider()
                    timeRow("From", minutes: $draft.startMinutes)
                    GlassRowDivider()
                    timeRow("Until", minutes: $draft.endMinutes)
                    GlassRowDivider()
                    DayPicker(days: $draft.unlockDays)
                        .padding(.vertical, Space.md)
                }
                Segmented(title: "Each unlock lasts", options: [5, 15, 30], selection: $draft.unlockMinutes) { "\($0) min" }
                    .padding(.top, Space.sm)
                if let until = routine.grantExpiresAt {
                    note("Unlocked until \(until.formatted(date: .omitted, time: .shortened)).")
                } else if routine.isShieldUp {
                    note("Your apps are shielded now. Speak to open them.")
                }
            }
        }
        .onChange(of: draft.startMinutes) { _, _ in applyUnlockIfOn() }
        .onChange(of: draft.endMinutes) { _, _ in applyUnlockIfOn() }
        .onChange(of: draft.unlockDays) { _, _ in applyUnlockIfOn() }
        .onChange(of: draft.unlockMinutes) { _, _ in applyUnlockIfOn() }
    }

    private func setUnlock(_ on: Bool) {
        notice = nil
        if on {
            do {
                try routine.enableUnlock(draft)
                Haptics.success()
                Analytics.action("routine_unlock_on")
            } catch {
                notice = (error as? LocalizedError)?.errorDescription
                if case RoutineStore.RoutineError.noSelection = error { picking = true }
            }
        } else {
            routine.disableUnlock()
            Analytics.action("routine_unlock_off")
        }
    }

    private func applyUnlockIfOn() {
        guard routine.settings.unlockEnabled else { return }
        do { try routine.enableUnlock(draft); notice = nil } catch { notice = (error as? LocalizedError)?.errorDescription }
    }

    // MARK: Daily prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionTitle(text: "Daily prompt")
            GlassRowGroup {
                Toggle(isOn: Binding(get: { routine.settings.promptEnabled }, set: { on in savePrompt(enabled: on) })) {
                    rowLabel("Remind me", icon: "bell.fill")
                }
                .tint(Palette.coral)
                .frame(minHeight: 56)
                GlassRowDivider()
                timeRow("At", minutes: $draft.promptMinutes)
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
            notice = ok ? nil : "Notifications are off for Speaking Coach. Turn them on in Settings for the daily prompt."
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

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typeface.body(14))
            .foregroundStyle(Palette.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Seven round day toggles, Sunday first like the calendar.
struct DayPicker: View {
    @Binding var days: [Int]

    private static let symbols = Calendar.current.veryShortWeekdaySymbols

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(1...7, id: \.self) { day in
                let isOn = days.contains(day)
                Button {
                    Haptics.selection()
                    if isOn { days.removeAll { $0 == day } } else { days = (days + [day]).sorted() }
                } label: {
                    Text(Self.symbols[day - 1])
                        .font(Typeface.label(14))
                        .foregroundStyle(isOn ? .white : Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Circle().fill(isOn ? Palette.coral : Palette.coral.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
