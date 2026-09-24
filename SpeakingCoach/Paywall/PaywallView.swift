import StoreKit
import SwiftUI

/// The onboarding's closing beat, built on JournalBlock's paywall: the
/// headline repeats the user's own outcome, three benefits restate the plan
/// they just committed to (the third written for their pattern), and the two
/// plans sit side by side so the yearly price is read *against* the monthly
/// one.
///
/// Pricing hierarchy (App Store Guideline 3.1.2(c)): on each card the
/// **billed amount** for the plan's own period is the largest price. The
/// struck-through anchor, the savings sticker and the trial are always
/// smaller. The headline carries no price and no trial.
struct PaywallView: View {
    let model: AppModel
    /// First-run wall: no ✕. Later presentations pass a close action.
    var onClose: (() -> Void)?

    @State private var selectedID: String?
    @State private var purchasing = false
    @State private var notice: (text: String, isError: Bool)?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var subscriptions: Subscriptions { model.subscriptions }
    private var profile: CoachProfile? { model.profile }
    private var selected: Plan? {
        subscriptions.plans.first { $0.id == selectedID } ?? subscriptions.plans.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // Flexible gaps absorb the slack on tall screens and collapse to
            // their minimum on small ones, so the plans never slide under
            // the footer.
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        headline
                        Spacer(minLength: Space.xxl).frame(maxHeight: 48)
                        benefits
                        Spacer(minLength: Space.xxl).frame(maxHeight: 56)
                        plans
                        if let notice {
                            Text(notice.text)
                                .font(Typeface.body(14))
                                .foregroundStyle(notice.isError ? Palette.danger : Palette.coralDeep)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                                .padding(.top, Space.lg)
                        }
                        // At accessibility sizes the footer needs more than
                        // half the screen; pinned, it would crush the plans.
                        if typeSize.isAccessibilitySize { footer.padding(.top, Space.lg) }
                        // Clears the edge fade, so the last line is read,
                        // not dissolved.
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, Space.xxl)
                    .padding(.top, Space.xxxl)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
                // Content dissolves into the stage above the footer.
                .bottomEdgeFade()
            }

            if !typeSize.isAccessibilitySize { footer }
        }
        .overlay(alignment: .topTrailing) {
            if let onClose {
                GlassIconButton(systemImage: "xmark", size: 40, iconSize: 14, color: Palette.dim, accessibilityLabel: "Close", action: onClose)
                    .padding(.trailing, Space.xl)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: notice?.text)
        .animation(.easeOut(duration: 0.3), value: subscriptions.plans)
        .task {
            Analytics.enter("paywall")
            if subscriptions.plansState != .loaded { await subscriptions.loadPlans() }
        }
    }

    // MARK: Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(Self.headline(for: profile))
                .font(Typeface.hero(30))
                .foregroundStyle(Palette.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The user's own outcome, as the promise. Falls back to the brand line
    /// for accounts that never answered (the old app's users).
    static func headline(for profile: CoachProfile?) -> String {
        guard let profile, let moment = profile.moment, !profile.outcomes.isEmpty else {
            return "Practise the conversations that matter."
        }
        if moment.isGeneral {
            let how = profile.outcomes.prefix(2).map(\.adverb).joined(separator: " and ")
            return "Speak \(how), every day."
        }
        let how = profile.outcomes.prefix(2).map(\.headlinePhrase).joined(separator: " and ")
        return moment == .meetingPeople ? "Walk into any room \(how)." : "Walk into \(moment.noun) \(how)."
    }

    // MARK: Benefits

    /// Three, each a reason rather than a feature: a crown, a bold lead and
    /// one line — JournalBlock's grammar.
    private var benefits: some View {
        let pattern = profile?.pattern ?? .steady
        let rehearse: String = switch profile?.moment {
        case .interview: "Your interview, out loud, with a partner who plays the other side."
        case .raise: "The raise conversation, out loud, with a manager who pushes back."
        case .hardConversation: "That conversation, out loud, before it happens for real."
        case .presentation: "Your opening, out loud, until it lands."
        case .speakingUp: "Your point, out loud, in a meeting that keeps moving."
        case .meetingPeople: "First conversations, out loud, with someone new."
        case .everyday: "Everyday conversations, out loud, with a partner who plays the other side."
        case .ielts: "Your speaking test, out loud, with an examiner who asks the real questions."
        case nil: "Real conversations, out loud, with a partner who plays the other side."
        }
        return VStack(alignment: .leading, spacing: 18) {
            BenefitRow(lead: "Practise it", detail: rehearse)
            BenefitRow(lead: "Hear it back", detail: "Feedback that quotes your own words.")
            BenefitRow(lead: "Retry the moment", detail: pattern.fix)
        }
    }

    // MARK: Plans

    @ViewBuilder
    private var plans: some View {
        VStack(spacing: Space.md) {
            Text("Select a plan that fits you")
                .font(Typeface.label(16))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)

            switch subscriptions.plansState {
            case .loaded:
                // Both options on screen at once: hiding the monthly price
                // removes the comparison that makes the yearly one a deal.
                HStack(alignment: .top, spacing: Space.md) {
                    ForEach(subscriptions.plans) { plan in
                        PricingCard(
                            plan: plan,
                            savings: plan.isAnnual ? subscriptions.annualSavingsPercent : nil,
                            isSelected: plan.id == selected?.id
                        ) {
                            Haptics.selection()
                            withAnimation(.easeOut(duration: 0.2)) { selectedID = plan.id }
                        }
                    }
                }
                // Both cards take their natural height, then match the
                // taller one — a two-line footnote must never squeeze the
                // price on its card.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10) // room for the sticker overhanging the yearly card
            case .failed:
                VStack(spacing: Space.md) {
                    Label("Plans couldn't load. Check your connection.", systemImage: "wifi.slash")
                        .font(Typeface.body(15))
                        .foregroundStyle(Palette.dim)
                    SecondaryButton(title: "Try again", systemImage: "arrow.clockwise") {
                        Task { await subscriptions.loadPlans() }
                    }
                }
                .padding(.vertical, Space.lg)
            case .idle, .loading:
                // Skeletons hold the cards' exact footprint, so nothing
                // jumps when the prices land.
                HStack(spacing: Space.md) {
                    PricingSkeleton()
                    PricingSkeleton()
                }
                .padding(.top, 10)
                .accessibilityLabel("Loading plans")
            }

            Text("Change plans or cancel anytime.")
                .font(Typeface.body(13))
                .foregroundStyle(Palette.dim)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Space.md) {
            PrimaryButton(title: purchasing ? "Just a moment…" : callToAction, systemImage: purchasing ? nil : "arrow.right", trailingIcon: true, action: buy)
                .disabled(selected == nil || purchasing)
                .animation(.easeInOut(duration: 0.2), value: callToAction)

            HStack(spacing: Space.lg) {
                footerLink("Restore") { Task { await restore() } }
                footerLink("Terms") { UIApplication.shared.open(AppConfig.termsURL) }
                footerLink("Privacy") { UIApplication.shared.open(AppConfig.privacyURL) }
                if onClose == nil {
                    // The only way off a hard paywall for the wrong account.
                    footerLink("Sign out") {
                        Task {
                            do {
                                try await model.signOut()
                            } catch {
                                notice = (error.localizedDescription, true)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Space.xxl)
        .padding(.top, Space.md)
        .padding(.bottom, Space.sm)
    }

    /// Names what the tap does for the plan that's selected — the trial
    /// length when there is one, otherwise the plan itself.
    private var callToAction: String {
        guard let selected else { return "Continue" }
        if let trial = selected.trialAdjective { return "Start \(trial) Free Trial" }
        return selected.isAnnual ? "Continue with Yearly" : "Continue with Monthly"
    }

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            Text(title)
                .font(Typeface.body(13))
                .foregroundStyle(Palette.dim)
                .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func buy() {
        guard let plan = selected, !purchasing else { return }
        purchasing = true
        notice = nil
        Analytics.action("paywall")
        Task {
            switch await subscriptions.purchase(plan) {
            case .purchased:
                Haptics.success()
            case .cancelled:
                break
            case .failed(let message):
                notice = (message, true)
                Haptics.error()
            }
            purchasing = false
        }
    }

    private func restore() async {
        notice = nil
        let result = await subscriptions.restore()
        notice = (result.message, result.isError)
    }
}

// MARK: - Pieces

private struct BenefitRow: View {
    let lead: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: "crown.fill")
                .font(.system(size: 17))
                .foregroundStyle(LinearGradient(colors: [Palette.peach, Palette.coral], startPoint: .top, endPoint: .bottom))
                .frame(width: 24, alignment: .leading)
                .padding(.top, 1)
                .accessibilityHidden(true)
            (Text("\(lead): ").font(Typeface.label(16)).foregroundColor(Palette.ink)
                + Text(detail).font(Typeface.body(16)).foregroundColor(Palette.dim))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// One plan, as a card beside its alternative. The billed price is the big
/// number; the anchor and the note are small and below it.
private struct PricingCard: View {
    let plan: Plan
    let savings: Int?
    let isSelected: Bool
    let action: () -> Void

    private let shape = RoundedRectangle(cornerRadius: Corner.lg, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(plan.name)
                        .font(Typeface.label(14))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: Space.xs)
                    SelectionCheck(isSelected: isSelected)
                }

                // A fixed gap, not a spacer: the prices must sit on one line
                // across both cards whatever their footnotes do.
                Text(plan.priceString)
                    .font(Typeface.title(26))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.xl)

                // Reserved even when absent, so both cards line up.
                Text(plan.anchorPriceString ?? " ")
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.dim)
                    .strikethrough(plan.anchorPriceString != nil, color: Palette.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)

                Spacer(minLength: Space.md)

                Text(footnote)
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, minHeight: 156, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: Corner.lg, tint: isSelected ? Palette.coral.opacity(0.16) : nil, interactive: true)
        .overlay {
            shape.strokeBorder(isSelected ? Palette.coral : Palette.border, lineWidth: isSelected ? 2 : 1)
        }
        // A sticker overhanging the top edge.
        .overlay(alignment: .top) {
            if let sticker {
                Text(sticker)
                    .font(Typeface.label(11))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.coral))
                    .offset(y: -11)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var sticker: String? {
        if let trial = plan.trialPhrase { return "\(trial.uppercased()) FREE" }
        return savings.map { "SAVE \($0)%" }
    }

    private var footnote: String {
        let cadence = plan.isAnnual ? "yearly" : "monthly"
        return plan.trialDays > 0 ? "Billed \(cadence) after the free trial." : "Billed \(cadence)."
    }
}

/// Mirrors `PricingCard`'s footprint, so the swap to prices is a fade.
private struct PricingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Capsule().fill(Palette.ink.opacity(0.08)).frame(width: 64, height: 12)
            Spacer(minLength: Space.lg)
            RoundedRectangle(cornerRadius: 6).fill(Palette.ink.opacity(0.08)).frame(width: 100, height: 24)
            Capsule().fill(Palette.ink.opacity(0.06)).frame(width: 90, height: 10)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .glassSurface(cornerRadius: Corner.lg)
    }
}

/// A solid, unmistakable selection mark: a filled coral disc with a white
/// check — never a thin ring you have to squint at.
struct SelectionCheck: View {
    let isSelected: Bool
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.ink.opacity(0.22), lineWidth: 1.5)
                .opacity(isSelected ? 0 : 1)
            Circle()
                .fill(Palette.coral)
                .opacity(isSelected ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(isSelected ? 1 : 0.5)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isSelected)
        .accessibilityHidden(true)
    }
}
