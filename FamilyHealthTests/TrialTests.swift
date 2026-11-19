import XCTest
@testable import FamilyHealth

final class TrialTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }

    private func status(
        at now: Date,
        lifetime: Bool = false,
        subscribedUntil: Date? = nil
    ) -> TrialStatus {
        TrialPolicy.status(trialStart: start, now: now, ownsLifetime: lifetime, subscribedUntil: subscribedUntil)
    }

    func testTrialCountsDownFourteenDays() {
        XCTAssertEqual(status(at: start), .trial(daysLeft: 14))
        XCTAssertEqual(status(at: day(0.5)), .trial(daysLeft: 14))
        XCTAssertEqual(status(at: day(1)), .trial(daysLeft: 13))
        XCTAssertEqual(status(at: day(13.9)), .trial(daysLeft: 1))
    }

    func testTrialEndsAfterFourteenDays() {
        XCTAssertEqual(status(at: day(14)), .ended)
        XCTAssertEqual(status(at: day(400)), .ended)
        XCTAssertFalse(TrialStatus.ended.canEdit)
        XCTAssertTrue(TrialStatus.trial(daysLeft: 1).canEdit)
        XCTAssertFalse(TrialStatus.ended.hasPlan)
        XCTAssertFalse(TrialStatus.trial(daysLeft: 5).hasPlan)
    }

    func testLifetimeWinsAtAnyTime() {
        XCTAssertEqual(status(at: day(3), lifetime: true), .lifetime)
        XCTAssertEqual(status(at: day(900), lifetime: true), .lifetime)
        // Lifetime also wins over an annual plan someone hasn't cancelled yet.
        XCTAssertEqual(status(at: day(30), lifetime: true, subscribedUntil: day(200)), .lifetime)
        XCTAssertTrue(TrialStatus.lifetime.canEdit)
        XCTAssertTrue(TrialStatus.lifetime.hasPlan)
    }

    func testActiveSubscriptionAllowsEditing() {
        // Apple's 14-day free trial of the annual plan counts as subscribed.
        XCTAssertEqual(status(at: day(1), subscribedUntil: day(15)), .subscribed(until: day(15)))
        XCTAssertEqual(status(at: day(100), subscribedUntil: day(380)), .subscribed(until: day(380)))
        XCTAssertTrue(TrialStatus.subscribed(until: day(380)).canEdit)
        XCTAssertTrue(TrialStatus.subscribed(until: day(380)).hasPlan)
    }

    func testLapsedSubscriptionFallsBackToTheTrialClock() {
        // Cancelled during Apple's free trial, still inside the 14 days.
        XCTAssertEqual(status(at: day(10), subscribedUntil: day(9)), .trial(daysLeft: 4))
        // Cancelled after a year: records are view-only again.
        XCTAssertEqual(status(at: day(400), subscribedUntil: day(380)), .ended)
        XCTAssertEqual(status(at: day(380), subscribedUntil: day(380)), .ended)
    }

    func testSettingTheClockBackDoesNotAddDays() {
        XCTAssertEqual(status(at: day(-30)), .trial(daysLeft: 14))
    }

    func testBannerShowsOnlyNearTheEnd() {
        XCTAssertFalse(TrialPolicy.showsBanner(.trial(daysLeft: 14)))
        XCTAssertFalse(TrialPolicy.showsBanner(.trial(daysLeft: 4)))
        XCTAssertTrue(TrialPolicy.showsBanner(.trial(daysLeft: 3)))
        XCTAssertTrue(TrialPolicy.showsBanner(.ended))
        XCTAssertFalse(TrialPolicy.showsBanner(.lifetime))
        XCTAssertFalse(TrialPolicy.showsBanner(.subscribed(until: day(30))))
        XCTAssertEqual(TrialPolicy.daysLeftText(1), "1 day left in your free trial")
        XCTAssertEqual(TrialPolicy.daysLeftText(3), "3 days left in your free trial")
    }

    func testPlansAreOfferedOnceAfterTheFirstPerson() {
        XCTAssertTrue(TrialPolicy.offersPlansAfterAddingPerson(.trial(daysLeft: 14), peopleCount: 1, alreadyOffered: false))
        XCTAssertFalse(TrialPolicy.offersPlansAfterAddingPerson(.trial(daysLeft: 14), peopleCount: 0, alreadyOffered: false))
        XCTAssertFalse(TrialPolicy.offersPlansAfterAddingPerson(.trial(daysLeft: 14), peopleCount: 2, alreadyOffered: true))
        XCTAssertFalse(TrialPolicy.offersPlansAfterAddingPerson(.lifetime, peopleCount: 1, alreadyOffered: false))
        XCTAssertFalse(TrialPolicy.offersPlansAfterAddingPerson(.subscribed(until: day(15)), peopleCount: 1, alreadyOffered: false))
        XCTAssertFalse(TrialPolicy.offersPlansAfterAddingPerson(.ended, peopleCount: 1, alreadyOffered: false))
    }

    func testFreeTrialLength() {
        XCTAssertEqual(TrialPolicy.trialLengthText(value: 2, unit: .week), "14 days")
        XCTAssertEqual(TrialPolicy.trialLengthText(value: 1, unit: .week), "7 days")
        XCTAssertEqual(TrialPolicy.trialLengthText(value: 3, unit: .day), "3 days")
        XCTAssertEqual(TrialPolicy.trialLengthText(value: 1, unit: .month), "1 month")
    }

    func testRenewalTermsSayPriceRenewalAndHowToCancel() {
        let withTrial = TrialPolicy.renewalTerms(yearlyPrice: "$9.99", freeTrial: "14 days")
        XCTAssertTrue(withTrial.hasPrefix("Free for 14 days, then $9.99 a year."))
        XCTAssertTrue(withTrial.contains("Renews automatically"))
        XCTAssertTrue(withTrial.contains("trial or year ends"))
        XCTAssertTrue(withTrial.contains("Cancel anytime"))

        let noTrial = TrialPolicy.renewalTerms(yearlyPrice: "$9.99", freeTrial: nil)
        XCTAssertTrue(noTrial.hasPrefix("$9.99 a year, billed to your Apple Account."))
        XCTAssertTrue(noTrial.contains("before the year ends"))
    }
}
