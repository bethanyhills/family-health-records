import Observation
import StoreKit
import SwiftUI

/// The two plans, through StoreKit 2:
/// - Annual: $9.99 a year, auto-renewing, starting with a 14-day free trial
///   (Apple's introductory offer) for people who haven't had one.
/// - Lifetime: $19.99 once.
/// Both are shared with the buyer's Family Sharing group. Without a plan,
/// records stay viewable and exportable (see `PlanPolicy`).
///
/// Nothing here talks to a server of ours. StoreKit checks purchases with
/// Apple on the device, and the app never sees who bought them.
@MainActor
@Observable
final class Purchases {
    static let annualProductID = "com.bethanyhills.FamilyHealth.annual"
    /// The lifetime plan keeps the product ID of the earlier one-time unlock,
    /// so anyone who bought the unlock in testing still owns it.
    static let lifetimeProductID = "com.bethanyhills.FamilyHealth.unlock"
    static let productIDs = [annualProductID, lifetimeProductID]

    private static let lifetimeKey = "isUnlocked"
    private static let subscribedUntilKey = "subscribedUntil"
    private static let inFreeTrialKey = "inFreeTrial"

    private(set) var annual: Product?
    private(set) var lifetime: Product?
    /// Whether this Apple Account can still get the annual plan's free trial.
    private(set) var isEligibleForFreeTrial = true
    private(set) var ownsLifetime: Bool
    private(set) var subscribedUntil: Date?
    private(set) var inFreeTrial = false
    private(set) var isPurchasing = false
    private(set) var didFailToLoad = false
    var message: String?
    /// Refreshed whenever the app comes forward, so an ended plan is noticed.
    var now = Date.now

    private var updates: Task<Void, Never>?

    init() {
        // The last known answers, so a locked screen doesn't flash at launch;
        // `refresh()` checks them against StoreKit right away.
        let defaults = UserDefaults.standard
        ownsLifetime = defaults.bool(forKey: Self.lifetimeKey)
        let until = defaults.double(forKey: Self.subscribedUntilKey)
        subscribedUntil = until > 0 ? Date(timeIntervalSince1970: until) : nil
        inFreeTrial = defaults.bool(forKey: Self.inFreeTrialKey)
    }

    var status: PlanStatus {
        PlanPolicy.status(
            now: now,
            ownsLifetime: ownsLifetime,
            subscribedUntil: subscribedUntil,
            inFreeTrial: inFreeTrial
        )
    }

    var access: RecordAccess { RecordAccess(canEdit: status.canEdit) }

    /// "$9.99" and "$19.99" from the App Store, in the person's own currency.
    var annualPrice: String? { annual?.displayPrice }
    var lifetimePrice: String? { lifetime?.displayPrice }

    /// "14 days" when the annual plan's free trial is available to this
    /// Apple Account, otherwise nil.
    var freeTrialText: String? {
        guard isEligibleForFreeTrial,
              let offer = annual?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let unit: PlanPolicy.TrialUnit = switch offer.period.unit {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        @unknown default: .day
        }
        return PlanPolicy.trialLengthText(value: offer.period.value * max(offer.periodCount, 1), unit: unit)
    }

    /// "Start your free trial", or "Choose a plan" for someone who already
    /// had one.
    var startTitle: String {
        freeTrialText == nil ? "Choose a plan" : "Start your free trial"
    }

    func start() async {
        if updates == nil {
            updates = Task { [weak self] in
                for await update in StoreKit.Transaction.updates {
                    await self?.handle(update)
                }
            }
        }
        await refresh()
        await loadProducts()
    }

    func loadProducts() async {
        if annual == nil || lifetime == nil {
            do {
                let products = try await Product.products(for: Self.productIDs)
                annual = products.first { $0.id == Self.annualProductID } ?? annual
                lifetime = products.first { $0.id == Self.lifetimeProductID } ?? lifetime
                didFailToLoad = annual == nil && lifetime == nil
            } catch {
                didFailToLoad = true
            }
        }
        if let subscription = annual?.subscription {
            isEligibleForFreeTrial = await subscription.isEligibleForIntroOffer
        }
    }

    /// Checks what this Apple Account (or its Family Sharing group) owns.
    /// Works offline from StoreKit's cache.
    func refresh() async {
        var lifetimeOwned = false
        var until: Date?
        var freeTrial = false
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case Self.lifetimeProductID:
                lifetimeOwned = true
            case Self.annualProductID:
                if var expires = transaction.expirationDate, expires >= (until ?? expires) {
                    // Still listed after its end date means Apple's billing
                    // grace period (a failed card being retried), so the plan
                    // keeps working. Check again tomorrow.
                    expires = max(expires, Date.now.addingTimeInterval(86_400))
                    until = expires
                    freeTrial = Self.isFreeTrial(transaction)
                }
            default:
                break
            }
        }
        setOwnership(lifetime: lifetimeOwned, subscribedUntil: until, inFreeTrial: freeTrial)
        now = .now
    }

    enum Plan { case annual, lifetime }

    func product(for plan: Plan) -> Product? {
        switch plan {
        case .annual: annual
        case .lifetime: lifetime
        }
    }

    func purchase(_ plan: Plan) async {
        if product(for: plan) == nil { await loadProducts() }
        guard let product = product(for: plan), !isPurchasing else {
            message = "The App Store isn't reachable right now. Check your connection and try again."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
            case .pending:
                message = "Your purchase is waiting for approval. Your plan starts as soon as it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "The purchase didn't go through. \(error.localizedDescription)"
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            message = "Couldn't reach the App Store. \(error.localizedDescription)"
            return
        }
        await refresh()
        await loadProducts()
        if !status.hasPlan {
            message = "No plan was found for this Apple Account."
        }
    }

    private func handle(_ verification: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = verification else { return }
        if Self.productIDs.contains(transaction.productID) {
            // New purchases, renewals, refunds, and family members joining or
            // leaving the Family Sharing group all land here. Someone may own
            // a plan more than one way, so check everything.
            await refresh()
            if transaction.productID == Self.annualProductID {
                isEligibleForFreeTrial = false
            }
        }
        await transaction.finish()
    }

    /// The subscription period that's Apple's free trial, not a paid year.
    private static func isFreeTrial(_ transaction: StoreKit.Transaction) -> Bool {
        if #available(iOS 17.2, *) {
            return transaction.offer?.type == .introductory && transaction.offer?.paymentMode == .freeTrial
        } else {
            return transaction.offerType == .introductory
        }
    }

    private func setOwnership(lifetime: Bool, subscribedUntil until: Date?, inFreeTrial freeTrial: Bool) {
        ownsLifetime = lifetime
        subscribedUntil = until
        inFreeTrial = freeTrial
        let defaults = UserDefaults.standard
        defaults.set(lifetime, forKey: Self.lifetimeKey)
        defaults.set(until?.timeIntervalSince1970 ?? 0, forKey: Self.subscribedUntilKey)
        defaults.set(freeTrial, forKey: Self.inFreeTrialKey)
    }
}
