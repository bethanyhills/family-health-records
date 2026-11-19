import Observation
import StoreKit
import SwiftUI

/// The 14-day trial and the two plans, through StoreKit 2:
/// - Annual: $9.99 a year, auto-renewing, with a 14-day free trial (Apple's
///   introductory offer) for people who haven't had one.
/// - Lifetime: $19.99 once.
/// Both are shared with the buyer's Family Sharing group.
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
    private static let offeredPlansKey = "didOfferPlans"

    private(set) var annual: Product?
    private(set) var lifetime: Product?
    /// Whether this Apple Account can still get the annual plan's free trial.
    private(set) var isEligibleForFreeTrial = true
    private(set) var ownsLifetime: Bool
    private(set) var subscribedUntil: Date?
    private(set) var isPurchasing = false
    private(set) var didFailToLoad = false
    private(set) var trialStart: Date
    var message: String?
    /// Refreshed whenever the app comes forward, so the trial counts down.
    var now = Date.now

    private var updates: Task<Void, Never>?

    init() {
        trialStart = TrialClock.start()
        #if DEBUG
        // For trying the trial in Xcode: add the launch argument
        // `-trialDaysUsed 15` to the scheme to see the trial as ended.
        if UserDefaults.standard.object(forKey: "trialDaysUsed") != nil {
            let used = UserDefaults.standard.integer(forKey: "trialDaysUsed")
            trialStart = Date.now.addingTimeInterval(-TimeInterval(used) * 86_400)
        }
        #endif
        // The last known answers, so a locked screen doesn't flash at launch;
        // `refresh()` checks them against StoreKit right away.
        let defaults = UserDefaults.standard
        ownsLifetime = defaults.bool(forKey: Self.lifetimeKey)
        let until = defaults.double(forKey: Self.subscribedUntilKey)
        subscribedUntil = until > 0 ? Date(timeIntervalSince1970: until) : nil
    }

    var status: TrialStatus {
        TrialPolicy.status(
            trialStart: trialStart,
            now: now,
            ownsLifetime: ownsLifetime,
            subscribedUntil: subscribedUntil
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
        let unit: TrialPolicy.TrialUnit = switch offer.period.unit {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        @unknown default: .day
        }
        return TrialPolicy.trialLengthText(value: offer.period.value * max(offer.periodCount, 1), unit: unit)
    }

    /// "Plans from $9.99 a year" for banners, without a price if the App
    /// Store hasn't answered yet.
    var plansFromText: String {
        annualPrice.map { "Plans from \($0) a year" } ?? "See plans"
    }

    /// Whether the plans screen should open by itself now (see `TrialPolicy`).
    func shouldOfferPlans(peopleCount: Int) -> Bool {
        let offered = UserDefaults.standard.bool(forKey: Self.offeredPlansKey)
        guard TrialPolicy.offersPlansAfterAddingPerson(status, peopleCount: peopleCount, alreadyOffered: offered) else {
            return false
        }
        UserDefaults.standard.set(true, forKey: Self.offeredPlansKey)
        return true
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
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case Self.lifetimeProductID:
                lifetimeOwned = true
            case Self.annualProductID:
                if let expires = transaction.expirationDate {
                    until = max(until ?? expires, expires)
                }
            default:
                break
            }
        }
        setOwnership(lifetime: lifetimeOwned, subscribedUntil: until)
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

    private func setOwnership(lifetime: Bool, subscribedUntil until: Date?) {
        ownsLifetime = lifetime
        subscribedUntil = until
        let defaults = UserDefaults.standard
        defaults.set(lifetime, forKey: Self.lifetimeKey)
        defaults.set(until?.timeIntervalSince1970 ?? 0, forKey: Self.subscribedUntilKey)
    }
}
