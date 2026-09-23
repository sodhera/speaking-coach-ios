import SwiftUI

/// The payoff: one clear read, one thing to keep (in the user's own words),
/// one thing to change — and the chance to go straight back to the exact
/// moment and try it again. The full criteria and transcript wait behind a
/// door for anyone who wants them.
///
/// Honest by construction: every quote is a line the user actually said
/// (the server rejects any assessment that cites words not in the
/// transcript), a retry's comparison is one criterion on one rubric and says
/// so, and nothing here rates accent, confidence or personality.
struct DebriefView: View {
    let report: PracticeReport
    let definition: PracticeDefinition
    /// False when this rehearsal's one retry has already been used.
    var retryAvailable = true
    var onRetry: (() -> Void)?
    var onRehearseAgain: (() -> Void)?
    let onDone: () -> Void

    @State private var showsDetails = false

    private var assessment: PracticeAssessment? { report.analysis.practice }
    private var comparison: RetryComparison? { RetryComparison(report: report) }
    private var checkpoint: RetryCheckpoint? { retryAvailable ? RetryCheckpoint.make(from: report) : nil }

    private var strength: CriterionResult? {
        assessment?.criteria.filter { $0.level > 0 }.max { $0.level < $1.level }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    HStack {
                        Kicker(text: comparison == nil ? (report.analysis.custom?.title ?? definition.title) : "Retry · \(definition.title)", color: Palette.coralDeep)
                        Spacer()
                        GlassIconButton(systemImage: "xmark", size: 40, iconSize: 14, color: Palette.dim, accessibilityLabel: "Close", action: onDone)
                    }

                    if let comparison {
                        whatChanged(comparison)
                            .revealIn(after: 0.1)
                    }

                    Text(assessment?.summary ?? report.analysis.summary ?? "Your rehearsal is saved.")
                        .font(Typeface.title(24))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .revealIn(after: comparison == nil ? 0.1 : 0.4)

                    if assessment == nil, let subscores = report.analysis.subscores, !subscores.isEmpty {
                        card(icon: "chart.bar.fill", title: "How it went", tint: Palette.coralDeep) {
                            ForEach(subscores, id: \.label) { subscore in
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    HStack {
                                        Text(subscore.label).font(Typeface.label(15)).foregroundStyle(Palette.ink)
                                        Spacer()
                                        Text(Self.band(subscore.score)).font(Typeface.body(13)).foregroundStyle(Palette.dim)
                                    }
                                    ScoreBar(value: Double(subscore.score) / 100)
                                    Text(subscore.note)
                                        .font(Typeface.body(14))
                                        .foregroundStyle(Palette.dim)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .revealIn(after: 0.35)
                    }

                    if assessment == nil, let improvements = report.analysis.improvements, !improvements.isEmpty {
                        card(icon: "arrow.turn.up.right", title: report.analysis.custom == nil ? "What to work on" : "Try these", tint: Palette.coralDeep) {
                            ForEach(Array(improvements.enumerated()), id: \.offset) { index, item in
                                HStack(alignment: .top, spacing: Space.sm) {
                                    Text("\(index + 1)")
                                        .font(Typeface.label(12))
                                        .foregroundStyle(.white)
                                        .frame(width: 20, height: 20)
                                        .background(Circle().fill(Palette.coral))
                                    Text(item).font(Typeface.body(16)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .revealIn(after: 0.6)
                    }

                    if assessment == nil, let rewrites = report.analysis.rewrites, !rewrites.isEmpty {
                        card(icon: "text.quote", title: "Say it better", tint: Palette.sage) {
                            ForEach(rewrites, id: \.original) { rewrite in
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text("You said").font(Typeface.label(12)).foregroundStyle(Palette.muted)
                                    quoteView(rewrite.original).opacity(0.75)
                                    Text("Try").font(Typeface.label(12)).foregroundStyle(Palette.sage).padding(.top, Space.xs)
                                    Text(rewrite.better)
                                        .font(Typeface.body(16))
                                        .foregroundStyle(Palette.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .revealIn(after: 0.85)
                    }

                    if let strength {
                        card(icon: "hand.thumbsup.fill", title: "Keep this", tint: Palette.sage) {
                            Text(strength.note)
                                .font(Typeface.body(16))
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if let quote = strength.evidence.first?.quote { quoteView(quote) }
                        }
                        .revealIn(after: 0.35)
                    }

                    if let adjustment = assessment?.adjustment {
                        card(icon: "arrow.turn.up.right", title: "Try one change", tint: Palette.coralDeep) {
                            Text(adjustment)
                                .font(Typeface.body(16))
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if let checkpoint, onRetry != nil {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text("The moment to retry")
                                        .font(Typeface.label(13))
                                        .foregroundStyle(Palette.muted)
                                    quoteView(checkpoint.prompt)
                                }
                                .padding(.top, Space.xs)
                            }
                        }
                        .revealIn(after: 0.6)
                    }

                    if assessment != nil {
                        card(icon: "figure.walk", title: "Take it into real life", tint: Palette.dim) {
                            Text(definition.transfer)
                                .font(Typeface.body(16))
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(definition.scaffold)
                                .font(Typeface.bodyItalic(15))
                                .foregroundStyle(Palette.dim)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .revealIn(after: 0.85)
                    }

                    QuietButton(title: showsDetails ? "Hide the details" : "See every criterion and the conversation", color: Palette.coralDeep) {
                        withAnimation(.easeInOut(duration: 0.3)) { showsDetails.toggle() }
                    }

                    if showsDetails { details.transition(.opacity) }

                    Text("Based on the words captured in this rehearsal — not a rating of your accent or personality.")
                        .font(Typeface.body(12))
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.lg)
                .padding(.bottom, Space.xxxl)
            }
            // Content dissolves into the stage above the actions.
            .bottomEdgeFade()

            actions
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.sm)
                .padding(.bottom, Space.sm)
        }
    }

    // MARK: Actions

    /// The retry leads when there's a moment to go back to — the fastest way
    /// from "try one change" to having actually tried it.
    @ViewBuilder
    private var actions: some View {
        if checkpoint != nil, let onRetry {
            VStack(spacing: Space.xs) {
                PrimaryButton(title: "Retry this moment · 90 sec", systemImage: "arrow.counterclockwise", action: onRetry)
                QuietButton(title: "Done", action: onDone)
            }
        } else if comparison != nil || report.analysis.custom != nil, let onRehearseAgain {
            VStack(spacing: Space.xs) {
                PrimaryButton(title: "Done", action: onDone)
                QuietButton(title: report.analysis.custom == nil ? "Rehearse the whole scene again" : "Rehearse it again", color: Palette.coralDeep, action: onRehearseAgain)
            }
        } else {
            PrimaryButton(title: "Done", action: onDone)
        }
    }

    // MARK: What changed

    private func whatChanged(_ comparison: RetryComparison) -> some View {
        let headline = comparison.change > 0
            ? "Clearer this time."
            : comparison.change == 0 ? "The same level, so far." : "This one needs another go."
        let label = definition.criteria.first { $0.id == comparison.after.id }?.label ?? "The moment you retried"
        return VStack(alignment: .leading, spacing: Space.lg) {
            HStack(spacing: Space.sm) {
                GlassRowIcon(icon: "arrow.left.arrow.right", color: comparison.change > 0 ? Palette.sage : Palette.coralDeep)
                Text("What changed")
                    .font(Typeface.label(16))
                    .foregroundStyle(Palette.ink)
            }
            Text(headline)
                .font(Typeface.title(22))
                .foregroundStyle(comparison.change > 0 ? Palette.sage : Palette.ink)
            Text(label)
                .font(Typeface.body(15))
                .foregroundStyle(Palette.dim)
                .fixedSize(horizontal: false, vertical: true)
            beforeAfterRow("Before", comparison.before, faded: true)
            beforeAfterRow("Now", comparison.after, faded: false)
            Text("One rehearsal compared with one retry — a direction, not proof of lasting change.")
                .font(Typeface.body(12))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Corner.xl, tint: comparison.change > 0 ? Palette.sage.opacity(0.08) : nil)
    }

    private func beforeAfterRow(_ title: String, _ result: CriterionResult, faded: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(title)
                    .font(Typeface.label(14))
                    .foregroundStyle(faded ? Palette.muted : Palette.ink)
                Spacer()
                LevelDots(level: result.level)
                Text(Self.levelName(result.level))
                    .font(Typeface.body(13))
                    .foregroundStyle(faded ? Palette.muted : Palette.dim)
            }
            if let quote = result.evidence.first?.quote {
                quoteView(quote).opacity(faded ? 0.7 : 1)
            }
        }
    }

    /// Words, not a bare number: a score out of 100 means nothing on its own.
    static func band(_ score: Int) -> String {
        score >= 75 ? "Strong" : score >= 50 ? "Getting there" : "Needs work"
    }

    static func levelName(_ level: Int) -> String {
        ["Not yet", "Partly", "Clearly"][min(max(level, 0), 2)]
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if let assessment {
                ForEach(assessment.criteria, id: \.id) { criterion in
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack(alignment: .top) {
                            Text(definition.criteria.first { $0.id == criterion.id }?.label ?? "Criterion")
                                .font(Typeface.label(15))
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: Space.md)
                            LevelDots(level: criterion.level)
                        }
                        Text(criterion.note)
                            .font(Typeface.body(14))
                            .foregroundStyle(Palette.dim)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(criterion.evidence, id: \.turnId) { evidence in quoteView(evidence.quote) }
                    }
                    .padding(Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: Corner.lg)
                }
            }
            if !report.transcript.isEmpty {
                VStack(alignment: .leading, spacing: Space.md) {
                    Kicker(text: "The conversation")
                    ForEach(report.transcript) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.role == .user ? "You" : definition.partner)
                                .font(Typeface.label(12))
                                .foregroundStyle(line.role == .user ? Palette.coralDeep : Palette.muted)
                            Text(line.text)
                                .font(Typeface.body(15))
                                .foregroundStyle(Palette.ink)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(cornerRadius: Corner.lg)
            }
        }
    }

    // MARK: Pieces

    private func card<Content: View>(icon: String, title: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                GlassRowIcon(icon: icon, color: tint)
                Text(title)
                    .font(Typeface.label(16))
                    .foregroundStyle(Palette.ink)
            }
            content()
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Corner.xl)
    }

    private func quoteView(_ quote: String) -> some View {
        Text("“\(quote)”")
            .font(Typeface.bodyItalic(15))
            .foregroundStyle(Palette.dim)
            .padding(.leading, Space.md)
            .overlay(alignment: .leading) {
                Rectangle().fill(Palette.coral.opacity(0.5)).frame(width: 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

/// A thin coral bar, 0…1.
private struct ScoreBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [Palette.peach, Palette.coral], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// Two dots filled by level: none (not yet observed), one (partly), two (clearly).
struct LevelDots: View {
    let level: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .fill(index < level ? Palette.coral : Palette.faint)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(["Not yet observed", "Partly demonstrated", "Clearly demonstrated"][min(max(level, 0), 2)])
    }
}
