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
            #if DEBUG
            // The review screens show a stage; they never connect.
            if LaunchFlags.value("-review-screen") != nil { return }
            #endif
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
                Text("Getting your partner")
                    .font(Typeface.label(14))
                    .foregroundStyle(Palette.dim)
                    .overlay(alignment: .trailing) {
                        WaitingDots(font: Typeface.label(14), color: Palette.dim)
                            .alignmentGuide(.trailing) { $0[.leading] }
                    }
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
                Text("Finding one useful change")
                    .font(Typeface.title(24))
                    .foregroundStyle(Palette.ink)
                    .overlay(alignment: .trailing) {
                        WaitingDots(font: Typeface.title(24), color: Palette.ink)
                            .alignmentGuide(.trailing) { $0[.leading] }
                    }
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
            title: "Your last session was cut short",
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
        if failure.offersFresh {
            return StatusScreen.Action(title: "Practise the whole scene") { Task { await session.startFresh() } }
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
    @State private var confirmingFinish = false

    private var voice: VoiceSession { session.voice }

    private var level: Double {
        voice.isPaused ? 0 : max(voice.outputLevel, voice.inputLevel * 0.85)
    }

    /// Who has the floor, in the plainest words: the partner by name while
    /// they talk, "Your turn" once it's the user's.
    private var status: String {
        if voice.isPaused { return showsHelp ? "Take your time" : "Paused" }
        if voice.partnerSpeaking { return session.definition.partner }
        return voice.userTurns == 0 && voice.lastPartnerLine == nil ? "About to begin" : "Your turn"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.md)

            Spacer(minLength: Space.xl)

            VStack(spacing: Space.xxl) {
                BloomMark(size: 120, color: voice.isPaused ? Palette.muted : Palette.coral, level: level)
                    .animation(.easeInOut(duration: 0.4), value: voice.isPaused)
                VStack(spacing: Space.md) {
                    Text(status)
                        .font(Typeface.label(14))
                        .foregroundStyle(voice.partnerSpeaking ? Palette.coralDeep : Palette.dim)
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
            GlassIconButton(systemImage: "xmark", size: 44, iconSize: 15, color: Palette.dim, accessibilityLabel: "Leave session") {
                // Nothing said yet: leaving costs nothing. Otherwise it's a
                // consequential exit, so it asks — honestly — first.
                if voice.userTurns == 0 { onLeave() } else { confirmingLeave = true }
            }
            .confirmationDialog("Leave this session?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Get feedback on what I said") { Task { await session.finish() } }
                Button("Leave without feedback", role: .destructive, action: onLeave)
            } message: {
                Text("What you've said so far is saved.")
            }
            Spacer()
            // Just the time: the question is on screen, and the session was
            // chosen a moment ago. The last half-minute turns coral, so the
            // end never arrives as a surprise.
            Text(session.isRetry ? "Retry · \(timeLabel)" : timeLabel)
                .font(Typeface.label(15))
                .foregroundStyle(isEnding ? Palette.coralDeep : Palette.dim)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: isEnding)
            Spacer()
            // Keeps the title centred against the ✕.
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var isEnding: Bool { voice.remaining > 0 && voice.remaining <= 30 }

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
            .glassSurface(cornerRadius: Corner.lg)
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
            // Only once there's something to get feedback on; before that
            // the ✕ is the way out, and a third button was just noise. Its
            // room is always kept, so the bloom never jumps mid-sentence.
            Button {
                confirmingFinish = true
            } label: {
                Label("Finish and get feedback", systemImage: "checkmark")
                    .font(Typeface.label(16))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassSurface(cornerRadius: 999, interactive: true)
            .opacity(voice.userTurns > 0 ? 1 : 0)
            .allowsHitTesting(voice.userTurns > 0)
            .accessibilityHidden(voice.userTurns == 0)
            .confirmationDialog("Ready for feedback?", isPresented: $confirmingFinish, titleVisibility: .visible) {
                Button("Finish and get feedback") { Task { await session.finish() } }
                Button("Keep speaking", role: .cancel) { }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: voice.userTurns > 0)
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

/// Three dots that fill in one at a time and start over, so a wait reads
/// as something happening. Every dot keeps its place while hidden, so the
/// words beside them never shift. Reduce Motion gets a still ellipsis.
struct WaitingDots: View {
    let font: Font
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { context in
            let step = reduceMotion ? 3 : Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 4
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    Text(".")
                        .opacity(index < step ? 1 : 0)
                }
            }
            .font(font)
            .foregroundStyle(color)
            .animation(.easeOut(duration: 0.2), value: step)
        }
        .accessibilityHidden(true)
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
