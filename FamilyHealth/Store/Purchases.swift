import Observation
import StoreKit
import SwiftUI

/// The 14-day trial and the one-time unlock, through StoreKit 2.
///
/// Nothing here talks to a server of ours. StoreKit checks the purchase with
/// Apple on the device, and the app never sees who bought it.
@MainActor
@Observable
final class Purchases {
    static let unlockProductID = "com.bethanyhills.FamilyHealth.unlock"
    private static let unlockedKey = "isUnlocked"

    private(set) var product: Product?
    private(set) var isUnlocked: Bool
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
        // The last known answer, so a locked screen doesn't flash at launch;
        // `refresh()` checks it against StoreKit right away.
        isUnlocked = UserDefaults.standard.bool(forKey: Self.unlockedKey)
    }

    var status: TrialStatus {
        TrialPolicy.status(trialStart: trialStart, now: now, isUnlocked: isUnlocked)
    }

    var access: RecordAccess { RecordAccess(canEdit: status.canEdit) }

    /// "$6.99" from the App Store, in the person's own currency.
    var price: String? { product?.displayPrice }

    var unlockTitle: String { price.map { "Unlock for \($0)" } ?? "Unlock" }

    func start() async {
        if updates == nil {
            updates = Task { [weak self] in
                for await update in StoreKit.Transaction.updates {
                    await self?.handle(update)
                }
            }
        }
        await refresh()
        await loadProduct()
    }

    func loadProduct() async {
        guard product == nil else { return }
        do {
            product = try await Product.products(for: [Self.unlockProductID]).first
            didFailToLoad = product == nil
        } catch {
            didFailToLoad = true
        }
    }

    /// Checks what this Apple ID owns. Works offline from StoreKit's cache.
    func refresh() async {
        var owned = false
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.unlockProductID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setUnlocked(owned)
    }

    func purchase() async {
        if product == nil { await loadProduct() }
        guard let product, !isPurchasing else {
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
                message = "Your purchase is waiting for approval. It will unlock as soon as it's approved."
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
        if !isUnlocked {
            message = "No earlier purchase was found for this Apple ID."
        }
    }

    private func handle(_ verification: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = verification else { return }
        if transaction.productID == Self.unlockProductID {
            if transaction.revocationDate == nil {
                setUnlocked(true)
            } else {
                // A refund, or a family member leaving the Family Sharing group.
                // Someone may still own it another way, so check everything.
                await refresh()
            }
        }
        await transaction.finish()
    }

    private func setUnlocked(_ value: Bool) {
        isUnlocked = value
        UserDefaults.standard.set(value, forKey: Self.unlockedKey)
    }
}
