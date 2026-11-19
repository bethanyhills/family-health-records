import XCTest
@testable import FamilyHealth

final class PlanTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }

    private func status(
        at now: Date,
        lifetime: Bool = false,
        subscribedUntil: Date? = nil,
        inFreeTrial: Bool = false
    ) -> PlanStatus {
        PlanPolicy.status(now: now, ownsLifetime: lifetime, subscribedUntil: subscribedUntil, inFreeTrial: inFreeTrial)
    }

    func testNewInstallHasNoPlanAndIsViewOnly() {
        XCTAssertEqual(status(at: start), .noPlan)
        XCTAssertFalse(PlanStatus.noPlan.canEdit)
        XCTAssertFalse(PlanStatus.noPlan.hasPlan)
    }

    func testAppleFreeTrialAllowsEditing() {
        let trial = status(at: day(1), subscribedUntil: day(14), inFreeTrial: true)
        XCTAssertEqual(trial, .subscribed(until: day(14), inFreeTrial: true))
        XCTAssertTrue(trial.canEdit)
        XCTAssertTrue(trial.hasPlan)
    }

    func testPaidYearAllowsEditing() {
        XCTAssertEqual(status(at: day(100), subscribedUntil: day(379)), .subscribed(until: day(379), inFreeTrial: false))
        XCTAssertTrue(PlanStatus.subscribed(until: day(379), inFreeTrial: false).canEdit)
    }

    func testCancelledSubscriptionIsViewOnlyAfterItEnds() {
        // Cancelled during the free trial: nothing charged, view-only after day 14.
        XCTAssertEqual(status(at: day(14), subscribedUntil: day(14), inFreeTrial: true), .noPlan)
        XCTAssertEqual(status(at: day(400), subscribedUntil: day(379)), .noPlan)
    }

    func testLifetimeWinsAtAnyTime() {
        XCTAssertEqual(status(at: day(3), lifetime: true), .lifetime)
        XCTAssertEqual(status(at: day(900), lifetime: true), .lifetime)
        // Lifetime also wins over an annual plan someone hasn't cancelled yet.
        XCTAssertEqual(status(at: day(30), lifetime: true, subscribedUntil: day(200)), .lifetime)
        XCTAssertTrue(PlanStatus.lifetime.canEdit)
    }

    func testBannerShowsWithoutAPlanAndNearTheEndOfTheFreeTrial() {
        XCTAssertTrue(PlanPolicy.showsBanner(.noPlan, now: start))
        XCTAssertFalse(PlanPolicy.showsBanner(.lifetime, now: start))
        XCTAssertFalse(PlanPolicy.showsBanner(.subscribed(until: day(14), inFreeTrial: true), now: day(1)))
        XCTAssertFalse(PlanPolicy.showsBanner(.subscribed(until: day(14), inFreeTrial: true), now: day(10.5)))
        XCTAssertTrue(PlanPolicy.showsBanner(.subscribed(until: day(14), inFreeTrial: true), now: day(11)))
        // Paid years renew quietly, like any other subscription.
        XCTAssertFalse(PlanPolicy.showsBanner(.subscribed(until: day(2), inFreeTrial: false), now: day(1)))
    }

    func testTrialEndsText() {
        XCTAssertEqual(PlanPolicy.trialEndsText(until: day(14), now: day(13.5)), "Your free trial ends today")
        XCTAssertEqual(PlanPolicy.trialEndsText(until: day(14), now: day(11)), "Your free trial ends in 3 days")
        XCTAssertTrue(PlanPolicy.trialEndsText(until: day(14), now: start).hasPrefix("Free trial until "))
    }

    func testFreeTrialLength() {
        XCTAssertEqual(PlanPolicy.trialLengthText(value: 2, unit: .week), "14 days")
        XCTAssertEqual(PlanPolicy.trialLengthText(value: 1, unit: .week), "7 days")
        XCTAssertEqual(PlanPolicy.trialLengthText(value: 3, unit: .day), "3 days")
        XCTAssertEqual(PlanPolicy.trialLengthText(value: 1, unit: .month), "1 month")
    }

    func testRenewalTermsSayPriceRenewalAndHowToCancel() {
        let withTrial = PlanPolicy.renewalTerms(yearlyPrice: "$9.99", freeTrial: "14 days")
        XCTAssertTrue(withTrial.hasPrefix("Free for 14 days, then $9.99 a year."))
        XCTAssertTrue(withTrial.contains("won't be charged"))
        XCTAssertTrue(withTrial.contains("Renews automatically"))
        XCTAssertTrue(withTrial.contains("trial or year ends"))
        XCTAssertTrue(withTrial.contains("Cancel anytime"))

        let noTrial = PlanPolicy.renewalTerms(yearlyPrice: "$9.99", freeTrial: nil)
        XCTAssertTrue(noTrial.hasPrefix("$9.99 a year, billed to your Apple Account."))
        XCTAssertTrue(noTrial.contains("before the year ends"))
    }
}
