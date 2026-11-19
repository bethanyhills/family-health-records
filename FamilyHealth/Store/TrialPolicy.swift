import Foundation

/// Where the app stands on the free trial and the two paid plans.
enum TrialStatus: Equatable {
    /// The one-time lifetime purchase.
    case lifetime
    /// The annual subscription, including Apple's free-trial weeks.
    case subscribed(until: Date)
    /// The free trial that needs no sign-up, counted on this iPhone.
    case trial(daysLeft: Int)
    case ended

    /// Adding and editing are allowed during the trial and on either plan.
    /// Records always stay viewable and exportable either way.
    var canEdit: Bool { self != .ended }

    /// On a paid plan (or in Apple's free trial of the annual plan).
    var hasPlan: Bool {
        switch self {
        case .lifetime, .subscribed: true
        case .trial, .ended: false
        }
    }
}

/// The rules for the 14-day trial and the plans, kept free of StoreKit so
/// they can be tested.
///
/// Pricing: $9.99 a year (auto-renewing, with a 14-day free trial through
/// Apple) or $19.99 once for lifetime access. Both include Family Sharing.
/// Someone who would rather not sign up yet gets the same 14 days counted
/// on the phone, then picks a plan.
enum TrialPolicy {
    static let length = 14
    /// The quiet banner on the Family screen appears only in the last few days.
    static let bannerDays = 3

    static func status(
        trialStart: Date,
        now: Date,
        ownsLifetime: Bool,
        subscribedUntil: Date?
    ) -> TrialStatus {
        if ownsLifetime { return .lifetime }
        // StoreKit only lists subscriptions that are current, but the app can
        // stay open past the end date, so check it here too.
        if let subscribedUntil, subscribedUntil > now { return .subscribed(until: subscribedUntil) }
        let end = trialStart.addingTimeInterval(TimeInterval(length) * 86_400)
        let remaining = end.timeIntervalSince(now)
        guard remaining > 0 else { return .ended }
        // A clock set back before the trial started never adds days.
        let days = Int((remaining / 86_400).rounded(.up))
        return .trial(daysLeft: min(days, length))
    }

    static func showsBanner(_ status: TrialStatus) -> Bool {
        switch status {
        case .lifetime, .subscribed: false
        case .ended: true
        case .trial(let daysLeft): daysLeft <= bannerDays
        }
    }

    /// The plans screen opens by itself once: right after the first family
    /// member is added, while the no-sign-up trial is running. Never again
    /// after that, and never for someone already on a plan.
    static func offersPlansAfterAddingPerson(
        _ status: TrialStatus,
        peopleCount: Int,
        alreadyOffered: Bool
    ) -> Bool {
        guard !alreadyOffered, peopleCount > 0 else { return false }
        if case .trial = status { return true }
        return false
    }

    static func daysLeftText(_ daysLeft: Int) -> String {
        daysLeft == 1 ? "1 day left in your free trial" : "\(daysLeft) days left in your free trial"
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
        let start = freeTrial.map { "Free for \($0), then \(price)." } ?? "\(price.prefix(1).uppercased() + price.dropFirst()), billed to your Apple Account."
        return "\(start) Renews automatically each year unless you cancel at least 24 hours before the \(freeTrial == nil ? "year" : "trial or year") ends. Cancel anytime in Settings > your name > Subscriptions."
    }
}
