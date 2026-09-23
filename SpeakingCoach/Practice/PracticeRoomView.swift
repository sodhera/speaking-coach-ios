import SwiftUI

/// The rehearsal, full screen. Built like SleepBlock's sleep mode: one living
/// object is the *state* — the bloom, opening with whoever is speaking — and
/// the words are the *instrument*: your partner's line as a caption beneath
/// it. Everything else waits at the thumb.
///
/// Control grammar, also SleepBlock's: consequential exits take a deliberate
/// confirmation; harmless ones are taps. Ending sends your words for feedback,
/// so it's a 1.2s hold. Pausing and asking for help cost nothing — taps.
struct PracticeSessionView: View {
    @State var session: PracticeSession
    /// Whether a report's one focused retry is still unused.
    var canRetry: (UUID) -> Bool = { _ in true }
    let onClose: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            MorningStage(depth: 1, ripples: false)
            Group {
                switch session.stage {
                case .preparing:
                    connecting
                case .live:
                    PracticeRoom(session: session, onLeave: leave)
                case .assessing:
                    assessing
                case .report(let report):
                    DebriefView(
                        report: report,
                        definition: session.definition,
                        retryAvailable: canRetry(report.id),
                        onRetry: { Task { await session.startRetry(from: report) } },
                        onRehearseAgain: { Task { await session.startFresh() } },
                        onDone: onClose
                    )
                case .recovery(let draft):
                    recovery(draft)
                case .failed(let failure):
                    failed(failure)
                }
            }
            .transition(.opacity)
        }
        .statusBarScrim()
        .animation(.easeInOut(duration: 0.35), value: session.stage)
        .task {
            if case .preparing = session.stage { await session.start() }
        }
        // The microphone must never stay live in the background: leaving the
        // app mid-scene ends it and keeps the words for feedback.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, case .live = session.stage {
                Task { await session.finish() }
            }
        }
        .persistentSystemOverlays(.hidden)
    }

    private func leave() {
        Task {
            await session.abandon()
            onClose()
        }
    }

    // MARK: States

    private var connecting: some View {
        VStack(spacing: Space.xxl) {
            BloomMark(size: 150)
            VStack(spacing: Space.sm) {
                Kicker(text: "Getting your partner")
                Text(session.definition.partner)
                    .font(Typeface.title(24))
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    private var assessing: some View {
        VStack(spacing: Space.xxl) {
            BloomMark(size: 150, level: 0.15)
            VStack(spacing: Space.sm) {
                Text("Finding one useful change…")
                    .font(Typeface.title(24))
                    .foregroundStyle(Palette.ink)
                Text("Reading your words against the goal.")
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.dim)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.xxl)
    }

    private func recovery(_ draft: PracticeDraft) -> some View {
        StatusScreen(
            title: "Your last rehearsal was cut short",
            message: "What you said is saved. Get feedback on it, or let it go.",
            primary: StatusScreen.Action(title: "Get my feedback") { Task { await session.assess(draft) } },
            secondary: StatusScreen.Action(title: "Let it go") {
                session.discardDraft()
                onClose()
            }
        )
    }

    private func failed(_ failure: PracticeSession.Failure) -> some View {
        StatusScreen(
            title: failure.title,
            message: failure.message,
            primary: primaryAction(for: failure),
            secondary: StatusScreen.Action(title: "Close", run: onClose)
        )
    }

    private func primaryAction(for failure: PracticeSession.Failure) -> StatusScreen.Action? {
        if failure.micDenied {
            return StatusScreen.Action(title: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
        if failure.canAssess {
            return StatusScreen.Action(title: "Try feedback again") { Task { await session.retryAssessment() } }
        }
        if failure.canRetry {
            return StatusScreen.Action(title: "Try again") { Task { await session.start() } }
        }
        return nil
    }
}

// MARK: - The live room

private struct PracticeRoom: View {
    let session: PracticeSession
    let onLeave: () -> Void

    @State private var showsHelp = false
    @State private var confirmingLeave = false

    private var voice: VoiceSession { session.voice }

    private var level: Double {
        voice.isPaused ? 0 : max(voice.outputLevel, voice.inputLevel * 0.85)
    }

    private var status: String {
        if voice.isPaused { return showsHelp ? "Take your time" : "Paused" }
        if voice.partnerSpeaking { return "Your partner is speaking" }
        return voice.userTurns == 0 && voice.lastPartnerLine == nil ? "Your partner is about to begin" : "Listening to you"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.md)

            Spacer(minLength: Space.xl)

            VStack(spacing: Space.xxl) {
                BloomMark(size: 210, color: voice.isPaused ? Palette.muted : Palette.coral, level: level)
                    .animation(.easeInOut(duration: 0.4), value: voice.isPaused)
                VStack(spacing: Space.md) {
                    Kicker(text: status, color: voice.partnerSpeaking ? Palette.coralDeep : Palette.dim)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: status)
                    caption
                }
                .padding(.horizontal, Space.xxl)
            }

            Spacer(minLength: Space.xl)

            controls
                .padding(.horizontal, Space.xxl)
                .padding(.bottom, Space.lg)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            GlassIconButton(systemImage: "xmark", size: 44, iconSize: 15, color: Palette.dim, accessibilityLabel: "Leave rehearsal") {
                // Nothing said yet: leaving costs nothing. Otherwise it's a
                // consequential exit, so it asks — honestly — first.
                if voice.userTurns == 0 { onLeave() } else { confirmingLeave = true }
            }
            .confirmationDialog("Leave this rehearsal?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Get feedback on what I said") { Task { await session.finish() } }
                Button("Leave without feedback", role: .destructive, action: onLeave)
            } message: {
                Text("What you've said so far is saved.")
            }
            Spacer()
            VStack(spacing: 2) {
                Text(session.isRetry ? "Retry · \(session.definition.title)" : session.definition.title)
                    .font(Typeface.label(15))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(timeLabel)
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.muted)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            // Keeps the title centred against the ✕.
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var timeLabel: String {
        let seconds = max(voice.remaining, 0)
        return seconds == 0 ? "Wrapping up" : String(format: "%d:%02d left", seconds / 60, seconds % 60)
    }

    /// The instrument: the partner's current line, or the scaffold while the
    /// user asked for help. Never the user's own words — they just said them.
    @ViewBuilder
    private var caption: some View {
        if showsHelp && voice.isPaused {
            VStack(spacing: Space.sm) {
                Text("Try starting with")
                    .font(Typeface.label(13))
                    .foregroundStyle(Palette.muted)
                Text(session.definition.scaffold)
                    .font(Typeface.title(19))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity)
            .glassSurface(cornerRadius: Corner.xl)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else if let line = voice.lastPartnerLine {
            Text(line)
                .font(Typeface.title(20))
                .foregroundStyle(Palette.ink.opacity(voice.isPaused ? 0.5 : 1))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.85)
                .id(line)
                .transition(.opacity)
        } else {
            Text(session.definition.objective)
                .font(Typeface.body(17))
                .foregroundStyle(Palette.dim)
                .multilineTextAlignment(.center)
        }
    }

    private var controls: some View {
        VStack(spacing: Space.md) {
            if voice.isPaused {
                PrimaryButton(title: "I'm ready", systemImage: "play.fill") {
                    showsHelp = false
                    voice.resume()
                }
            } else {
                GlassGroup(spacing: Space.md) {
                    HStack(spacing: Space.md) {
                        SmallCapsuleButton(title: "I need a moment", systemImage: "pause.fill") {
                            showsHelp = false
                            voice.pause()
                        }
                        SmallCapsuleButton(title: "Help me", systemImage: "lightbulb.fill") {
                            showsHelp = true
                            voice.pause()
                        }
                    }
                }
            }
            HoldCapsuleButton(title: voice.userTurns == 0 ? "Hold to end" : "Hold to finish & get feedback", systemImage: "checkmark") {
                Task { await session.finish() }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: voice.isPaused)
    }
}

private struct SmallCapsuleButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(Typeface.label(15))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: 999, interactive: true)
    }
}

/// A capsule you hold for 1.2s: coral fills it as you hold, heavy ticks
/// ratchet up, a double knock lands at the end, and letting go early springs
/// the fill back. Zero precision needed, and no stray tap can fire it.
struct HoldCapsuleButton: View {
    let title: String
    var systemImage: String?
    var duration: Double = 1.2
    let onComplete: () -> Void

    @State private var progress: Double = 0
    @State private var isHolding = false
    @State private var isComplete = false
    @State private var lastTick = -1
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Capsule(style: .continuous).fill(.clear).glassSurface(cornerRadius: 999, tint: Palette.glassCoral, interactive: true)
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [Palette.peach, Palette.coral], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * progress))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(Capsule(style: .continuous))
                Label {
                    Text(title).font(Typeface.label(16))
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .foregroundStyle(progress > 0.55 || isComplete ? .white : Palette.ink)
            }
            .shadow(color: Palette.coral.opacity(0.1 + progress * 0.35), radius: 12 + progress * 10, y: 4)
            .scaleEffect(isHolding ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: isHolding)
            .contentShape(Capsule(style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in startHold() }
                    .onEnded { _ in endHold() }
            )
        }
        .frame(height: 58)
        .onDisappear { holdTask?.cancel() }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Touch and hold to confirm.")
        .accessibilityAction { complete() }
    }

    private func startHold() {
        guard !isHolding, !isComplete else { return }
        isHolding = true
        lastTick = -1
        Haptics.rigid()
        holdTask = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                let p = min(1, Date().timeIntervalSince(start) / duration)
                progress = p
                let step = Int(p * 5)
                if step != lastTick {
                    lastTick = step
                    if step > 0 { Haptics.tick(0.7 + p * 0.3) }
                }
                if p >= 1 { complete(); break }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func complete() {
        guard !isComplete else { return }
        holdTask?.cancel()
        isComplete = true
        progress = 1
        Haptics.doubleHeavy()
        onComplete()
    }

    private func endHold() {
        holdTask?.cancel()
        isHolding = false
        guard !isComplete else { return }
        if progress > 0.02 { Haptics.soft() }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { progress = 0 }
    }
}

// MARK: - Status screen

/// A calm full-screen state: title, one line, one primary action, a quiet exit.
struct StatusScreen: View {
    struct Action {
        let title: String
        let run: () -> Void
    }

    let title: String
    let message: String
    var primary: Action?
    var secondary: Action?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            BloomMark(size: 96, glow: false)
            Text(title)
                .font(Typeface.hero(26))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.top, Space.xxl)
            Text(message)
                .font(Typeface.body(15))
                .foregroundStyle(Palette.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.md)
            Spacer()
            VStack(spacing: Space.sm) {
                if let primary { PrimaryButton(title: primary.title, action: primary.run) }
                if let secondary { QuietButton(title: secondary.title, action: secondary.run) }
            }
            .padding(.bottom, Space.lg)
        }
        .padding(.horizontal, Space.xxl)
    }
}
