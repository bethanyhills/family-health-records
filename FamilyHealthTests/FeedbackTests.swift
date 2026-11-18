import XCTest
@testable import FamilyHealth

final class FeedbackTests: XCTestCase {
    func testMailLinkHasSubjectBodyAndDetails() throws {
        let details = Feedback.deviceDetails(version: "1.2 (7)", system: "18.1", model: "iPhone")
        let url = try XCTUnwrap(Feedback.mailURL(.featureRequest, details: details, to: "help@example.com"))
        XCTAssertEqual(url.scheme, "mailto")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.path, "help@example.com")
        let items = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["subject"], "Family Health Binder feature request")
        let body = try XCTUnwrap(items["body"])
        XCTAssertTrue(body.hasPrefix("What would you like the app to do?"))
        XCTAssertTrue(body.contains("App version: 1.2 (7)\niOS: 18.1\nDevice: iPhone"))
        XCTAssertTrue(body.contains("Please don't include medical details"))
    }

    func testPlusSignsSurviveTheMailLink() throws {
        let url = try XCTUnwrap(Feedback.mailURL(.feedback, details: "Device: iPhone 15 Pro+"))
        XCTAssertFalse(url.absoluteString.contains("+"))
        XCTAssertTrue(url.absoluteString.contains("%2B"))
    }

    func testRatingLinkOnlyWithAnAppStoreID() {
        XCTAssertNil(Feedback.reviewURL(appStoreID: nil))
        XCTAssertNil(Feedback.reviewURL(appStoreID: ""))
        XCTAssertEqual(Feedback.reviewURL(appStoreID: "123456789")?.absoluteString,
                       "https://apps.apple.com/app/id123456789?action=write-review")
    }
}
