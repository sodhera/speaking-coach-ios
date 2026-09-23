import Foundation
import Observation
import RevenueCat
import Supabase

/// What the gate knows about access. `.unknown` means not resolved yet — the
/// gate never shows the paywall *or* the app off an unknown, only off an
/// answer.
enum Access: Equatable {
    case unknown, entitled, notEntitled
}

/// One purchasable plan, mapped out of RevenueCat so views never import it.
struct Plan: Identifiable, Equatable {
    let id: String
    let isAnnual: Bool
    let name: String
    /// The billed amount for the plan's own period — the largest price on the
    /// card, always (App Store Guideline 3.1.2(c)).
    let priceString: String
    let periodWord: String
    /// Annual only, subordinate: "$4.99/mo equivalent".
    let perMonthString: String?
    /// Days of free trial this user is eligible for; 0 when none.
    var trialDays: Int
    let priceValue: Decimal
    /// Annual only: twelve months of the monthly plan, in the product's own
    /// currency format — the struck-through anchor. Subordinate to the
    /// billed amount, always.
    var anchorPriceString: String?

    /// The trial in the words people use: "1 week", "2 weeks", "1 month",
    /// else "N days". Nil when there's no trial.
    var trialPhrase: String? {
        guard trialDays > 0 else { return nil }
        if trialDays % 30 == 0 { let m = trialDays / 30; return m == 1 ? "1 month" : "\(m) months" }
        if trialDays % 7 == 0 { let w = trialDays / 7; return w == 1 ? "1 week" : "\(w) weeks" }
        return trialDays == 1 ? "1 day" : "\(trialDays) days"
    }

    /// "1-Week", for a button title.
    var trialAdjective: String? {
        trialPhrase.map { phrase in
            phrase.split(separator: " ").enumerated().map { index, part in
                index == 1 ? String(part.hasSuffix("s") ? part.dropLast() : part).capitalized : String(part)
            }.joined(separator: "-")
        }
    }
}

/// Subscriptions through RevenueCat, keyed to the Supabase user id — the
/// same id the practice server checks, so app and server always agree.
///
/// Access is the `pro` entitlement *or* a comped account (the admin
/// dashboard's manual override / paid-email allowlist), matching the server's
/// own rule for starting a practice.
@MainActor
@Observable
final class Subscriptions {
    private(set) var access: Access = .unknown
    private(set) var plans: [Plan] = []
    private(set) var plansState: PlansState = .idle
    private(set) var willRenew = true
    private(set) var expiration: Date?

    enum PlansState: Equatable { case idle, loading, loaded, failed }

    static let entitlementID = "pro"
    private static let apiKey = "appl_OaMttJNWVFoVwBdoMwlKmzLukzB"

    private var packages: [String: Package] = [:]
    private var userID: UUID?
    private var comped = false
    private var streamTask: Task<Void, Never>?

    #if DEBUG
    /// `-review-access=entitled|notEntitled` pins the gate for layout review.
    private let pinned: Access? = LaunchFlags.value("-review-access").flatMap {
        $0 == "entitled" ? .entitled : $0 == "notEntitled" ? .notEntitled : nil
    }
    #else
    private let pinned: Access? = nil
    #endif

    func configure() {
        guard !Purchases.isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: Self.apiKey)
        streamTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
    }

    /// Ties purchases to the account. Called whenever the signed-in user changes.
    func identify(_ user: User?) async {
        configure()
        if let pinned { access = pinned; return }
        guard let user else {
            userID = nil
            comped = false
            access = .unknown
            if !Purchases.shared.isAnonymous { _ = try? await Purchases.shared.logOut() }
            return
        }
        guard user.id != userID else { return }
        userID = user.id
        access = .unknown
        comped = Self.hasManualPro(user)
        do {
            let (info, _) = try await Purchases.shared.logIn(user.id.uuidString.lowercased())
            if let email = user.email { Purchases.shared.attribution.setEmail(email) }
            apply(info)
        } catch {
            AppLog.error("RevenueCat logIn failed: \(error.localizedDescription)")
        }
        if access != .entitled, !comped {
            comped = await Self.fetchOverride(userID: user.id)
            if comped { access = .entitled }
        }
        // A failed lookup with no cached info still has to resolve somewhere:
        // the gate treats `.unknown` as "hold the splash", so give it an answer.
        if access == .unknown { access = comped ? .entitled : .notEntitled }
    }

    private func apply(_ info: CustomerInfo) {
        if let pinned { access = pinned; return }
        let entitlement = info.entitlements[Self.entitlementID]
        let active = entitlement?.isActive == true
        willRenew = entitlement?.willRenew ?? true
        expiration = entitlement?.expirationDate
        access = active || comped ? .entitled : .notEntitled
    }

    // MARK: Plans

    func loadPlans() async {
        guard plansState != .loading else { return }
        #if DEBUG
        if LaunchFlags.has("-review-plans") { return }
        #endif
        configure()
        plansState = .loading
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let offering = offerings.current, !offering.availablePackages.isEmpty else {
                plansState = .failed
                return
            }
            let available = offering.availablePackages.filter { [.annual, .monthly].contains($0.packageType) }
            let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(packages: available)
            #if DEBUG
            for package in available {
                let intro = package.storeProduct.introductoryDiscount
                AppLog.info("Plan \(package.storeProduct.productIdentifier): intro=\(intro.map { "\($0.paymentMode.rawValue) \($0.subscriptionPeriod.value) \($0.subscriptionPeriod.unit)" } ?? "none"), eligibility=\(eligibility[package]?.status.rawValue ?? -1)")
            }
            #endif
            packages = Dictionary(uniqueKeysWithValues: available.map { ($0.identifier, $0) })
            var mapped = available
                .map { Self.plan(from: $0, eligible: eligibility[$0]?.status == .eligible) }
                .sorted { $0.isAnnual && !$1.isAnnual }
            // The anchor: a year of the monthly plan, formatted by the annual
            // product's own formatter so the two prices can't mix styles.
            if let annualIndex = mapped.firstIndex(where: \.isAnnual),
               let monthly = mapped.first(where: { !$0.isAnnual }),
               let formatter = packages[mapped[annualIndex].id]?.storeProduct.priceFormatter {
                let yearOfMonthly = monthly.priceValue * 12
                if yearOfMonthly > mapped[annualIndex].priceValue {
                    mapped[annualIndex].anchorPriceString = formatter.string(from: yearOfMonthly as NSDecimalNumber)
                }
            }
            plans = mapped
            plansState = .loaded
        } catch {
            AppLog.error("Offerings failed: \(error.localizedDescription)")
            plansState = .failed
        }
    }

    private static func plan(from package: Package, eligible: Bool) -> Plan {
        let product = package.storeProduct
        let isAnnual = package.packageType == .annual
        var trialDays = 0
        if eligible, let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial {
            let period = intro.subscriptionPeriod
            switch period.unit {
            case .day: trialDays = period.value
            case .week: trialDays = period.value * 7
            case .month: trialDays = period.value * 30
            case .year: trialDays = period.value * 365
            @unknown default: trialDays = 0
            }
        }
        return Plan(
            id: package.identifier,
            isAnnual: isAnnual,
            name: isAnnual ? "Yearly" : "Monthly",
            priceString: product.localizedPriceString,
            periodWord: isAnnual ? "year" : "month",
            perMonthString: isAnnual ? product.localizedPricePerMonth : nil,
            trialDays: trialDays,
            priceValue: product.price
        )
    }

    /// The annual plan's saving against twelve months of the monthly plan,
    /// from the fetched prices — never a hard-coded figure.
    var annualSavingsPercent: Int? {
        guard let annual = plans.first(where: \.isAnnual), let monthly = plans.first(where: { !$0.isAnnual }) else { return nil }
        let yearOfMonthly = monthly.priceValue * 12
        guard yearOfMonthly > 0 else { return nil }
        // Through Double: NSDecimalNumber.intValue misreads long decimals.
        let fraction = NSDecimalNumber(decimal: annual.priceValue / yearOfMonthly).doubleValue
        let rounded = Int(((1 - fraction) * 100).rounded(.down))
        return rounded >= 5 ? rounded : nil
    }

    #if DEBUG
    func setReviewPlans(_ plans: [Plan]) {
        self.plans = plans
        plansState = .loaded
    }
    #endif

    // MARK: Purchase

    enum PurchaseOutcome { case purchased, cancelled, failed(String) }

    func purchase(_ plan: Plan) async -> PurchaseOutcome {
        guard let package = packages[plan.id] else { return .failed("That plan isn't available right now.") }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            apply(result.customerInfo)
            return access == .entitled ? .purchased : .failed("The purchase went through, but access didn't unlock. Try Restore.")
        } catch let error as RevenueCat.ErrorCode where error == .purchaseCancelledError {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Returns a notice for the paywall to show.
    func restore() async -> (message: String, isError: Bool) {
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            return access == .entitled
                ? ("Your subscription is back.", false)
                : ("No subscription to restore on this Apple ID.", false)
        } catch {
            return ("Restore didn't finish. Please try again.", true)
        }
    }

    // MARK: Comped accounts

    /// The admin dashboard writes this into `app_metadata`, which only the
    /// service role can set — safe to trust from the session.
    private static func hasManualPro(_ user: User) -> Bool {
        guard case .object(let override)? = user.appMetadata["admin_subscription_override"],
              case .string("pro")? = override["tier"] else { return false }
        guard case .string(let raw)? = override["expires_at"] else { return true }
        guard let date = ISO8601DateFormatter().date(from: raw) else { return false }
        return date > .now
    }

    /// The server also comps a paid-email allowlist the app can't see, so ask it.
    private static func fetchOverride(userID: UUID) async -> Bool {
        let url = AppConfig.apiBaseURL.appending(path: "api/subscription-overrides/\(userID.uuidString.lowercased())")
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try? JSONDecoder().decode([String: AnyJSON].self, from: data),
              case .string("pro")? = body["tier"] else { return false }
        return true
    }
}
