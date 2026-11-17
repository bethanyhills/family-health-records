import XCTest
@testable import FamilyHealth

final class TrialTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }

    func testTrialCountsDownFourteenDays() {
        XCTAssertEqual(TrialPolicy.status(trialStart: start, now: start, isUnlocked: false), .trial(daysLeft: 14))
        XCTAssertEqual(TrialPolicy.status(trialStart: start, now: day(0.5), isUnlocked: false), .trial(daysLeft: 14))
        XCTAssertEqual(TrialPolicy.status(trialStart: start, now: day(1), isUnlocked: false), .trial(daysLeft: 13))
        XCTAssertEqual(TrialPolicy.status(trialStart: start, now: day(13.9), isUnlocked: false), .trial(daysLeft: 1))
    }

    func testTrialEndsAfterFourteenDays() {
        XCTAssertEqual(TrialPolicy.status(trialStart: start, now: day(14), isUnlocked: false), .ended)
        XCTAssertEqual(TrialPolicy.status(trialStart: start, now: day(400), isUnlocked: false), .ended)
        XCTAssertFalse(TrialStatus.ended.canEdit)
        XCTAssertTrue(TrialStatus.trial(daysLeft: 1).canEdit)
    }

    func testUnlockWinsAtAnyTime() {
        XCTAssertEqual(TrialPolicy.status(trialStart: start, now: day(3), isUnlocked: true), .unlocked)
        XCTAssertEqual(TrialPolicy.status(trialStart: start, now: day(90), isUnlocked: true), .unlocked)
        XCTAssertTrue(TrialStatus.unlocked.canEdit)
    }

    func testSettingTheClockBackDoesNotAddDays() {
        XCTAssertEqual(TrialPolicy.status(trialStart: start, now: day(-30), isUnlocked: false), .trial(daysLeft: 14))
    }

    func testBannerShowsOnlyNearTheEnd() {
        XCTAssertFalse(TrialPolicy.showsBanner(.trial(daysLeft: 14)))
        XCTAssertFalse(TrialPolicy.showsBanner(.trial(daysLeft: 4)))
        XCTAssertTrue(TrialPolicy.showsBanner(.trial(daysLeft: 3)))
        XCTAssertTrue(TrialPolicy.showsBanner(.ended))
        XCTAssertFalse(TrialPolicy.showsBanner(.unlocked))
        XCTAssertEqual(TrialPolicy.daysLeftText(1), "1 day left in your free trial")
        XCTAssertEqual(TrialPolicy.daysLeftText(3), "3 days left in your free trial")
    }
}
