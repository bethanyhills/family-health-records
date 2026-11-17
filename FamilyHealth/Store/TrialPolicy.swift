import Foundation

/// Where the app stands on the free trial and the one-time unlock.
enum TrialStatus: Equatable {
    case unlocked
    case trial(daysLeft: Int)
    case ended

    /// Adding and editing are allowed during the trial and after unlocking.
    /// Records always stay viewable and exportable either way.
    var canEdit: Bool { self != .ended }
}

/// The rules for the 14-day trial, kept free of StoreKit so they can be tested.
enum TrialPolicy {
    static let length = 14
    /// The quiet banner on the Family screen appears only in the last few days.
    static let bannerDays = 3

    static func status(trialStart: Date, now: Date, isUnlocked: Bool) -> TrialStatus {
        if isUnlocked { return .unlocked }
        let end = trialStart.addingTimeInterval(TimeInterval(length) * 86_400)
        let remaining = end.timeIntervalSince(now)
        guard remaining > 0 else { return .ended }
        // A clock set back before the trial started never adds days.
        let days = Int((remaining / 86_400).rounded(.up))
        return .trial(daysLeft: min(days, length))
    }

    static func showsBanner(_ status: TrialStatus) -> Bool {
        switch status {
        case .unlocked: false
        case .ended: true
        case .trial(let daysLeft): daysLeft <= bannerDays
        }
    }

    static func daysLeftText(_ daysLeft: Int) -> String {
        daysLeft == 1 ? "1 day left in your free trial" : "\(daysLeft) days left in your free trial"
    }
}
