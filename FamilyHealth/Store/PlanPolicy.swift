import Foundation

/// Where this Apple Account (or its Family Sharing group) stands on the plans.
enum PlanStatus: Equatable {
    /// The one-time lifetime purchase.
    case lifetime
    /// The annual subscription. `inFreeTrial` is true during Apple's 14 free
    /// days, before the first $9.99 charge.
    case subscribed(until: Date, inFreeTrial: Bool)
    /// Never subscribed, or the subscription ended. Records stay viewable
    /// and exportable; adding and editing need a plan.
    case noPlan

    var canEdit: Bool { self != .noPlan }
    var hasPlan: Bool { self != .noPlan }
}

/// The pricing rules, kept free of StoreKit so they can be tested.
///
/// Pricing: $9.99 a year, auto-renewing, starting with a 14-day free trial
/// through Apple (cancel before it ends and nothing is charged), or $19.99
/// once for lifetime access. Both include Family Sharing. Apple doesn't let
/// an app start a subscription by itself, so on first launch the app asks
/// people to confirm the free trial with Apple.
enum PlanPolicy {
    /// The trial and banner reminders count down from here.
    static let reminderDays = 3

    static func status(
        now: Date,
        ownsLifetime: Bool,
        subscribedUntil: Date?,
        inFreeTrial: Bool
    ) -> PlanStatus {
        if ownsLifetime { return .lifetime }
        // StoreKit only lists subscriptions that are current, but the app can
        // stay open past the end date, so check it here too.
        if let subscribedUntil, subscribedUntil > now {
            return .subscribed(until: subscribedUntil, inFreeTrial: inFreeTrial)
        }
        return .noPlan
    }

    /// Whole days left before `date`, counting a part day as a day.
    static func daysLeft(until date: Date, now: Date) -> Int {
        max(0, Int((date.timeIntervalSince(now) / 86_400).rounded(.up)))
    }

    /// The Family screen shows a banner when there's no plan (records are
    /// view-only), and in the last few days of Apple's free trial so the
    /// first charge is never a surprise.
    static func showsBanner(_ status: PlanStatus, now: Date) -> Bool {
        switch status {
        case .lifetime: false
        case .noPlan: true
        case .subscribed(let until, let inFreeTrial):
            inFreeTrial && daysLeft(until: until, now: now) <= reminderDays
        }
    }

    static func trialEndsText(until: Date, now: Date) -> String {
        switch daysLeft(until: until, now: now) {
        case 0, 1: "Your free trial ends today"
        case let days where days <= 7: "Your free trial ends in \(days) days"
        default: "Free trial until \(until.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    /// "14 days" from Apple's free-trial period ("2 weeks").
    static func trialLengthText(value: Int, unit: TrialUnit) -> String {
        let days: Int
        switch unit {
        case .day: days = value
        case .week: days = value * 7
        case .month: return value == 1 ? "1 month" : "\(value) months"
        case .year: return value == 1 ? "1 year" : "\(value) years"
        }
        return days == 1 ? "1 day" : "\(days) days"
    }

    enum TrialUnit { case day, week, month, year }

    /// The words Apple requires next to a subscribe button: what it costs,
    /// that it renews by itself, and how to cancel.
    static func renewalTerms(yearlyPrice: String?, freeTrial: String?) -> String {
        let price = yearlyPrice.map { "\($0) a year" } ?? "the yearly price shown"
        let start: String
        if let freeTrial {
            start = "Free for \(freeTrial), then \(price). Cancel before the trial ends and you won't be charged."
        } else {
            start = "\(price.prefix(1).uppercased())\(price.dropFirst()), billed to your Apple Account."
        }
        return "\(start) Renews automatically each year unless you cancel at least 24 hours before the \(freeTrial == nil ? "year" : "trial or year") ends. Cancel anytime in Settings > your name > Subscriptions."
    }
}
