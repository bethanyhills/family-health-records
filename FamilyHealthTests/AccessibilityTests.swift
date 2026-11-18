import XCTest
@testable import FamilyHealth

final class AccessibilityTests: XCTestCase {
    /// Words and badges in every color meet WCAG AA (4.5:1) in light and dark mode.
    func testTextColorsAreReadable() {
        for (name, pair) in Theme.Pairs.textColors {
            for surface in Theme.lightSurfaces {
                XCTAssertGreaterThanOrEqual(Contrast.ratio(pair.light, surface), 4.5, "\(name) on light \(String(surface, radix: 16))")
            }
            for surface in Theme.darkSurfaces {
                XCTAssertGreaterThanOrEqual(Contrast.ratio(pair.dark, surface), 4.5, "\(name) on dark \(String(surface, radix: 16))")
            }
        }
    }

    /// Badges draw the color on a 15% tint of itself, like "Severe" on an allergy.
    func testBadgesAreReadable() {
        for (name, pair) in Theme.Pairs.textColors {
            let lightBadge = Contrast.blend(pair.light, over: 0xFFFFFF, opacity: 0.15)
            let darkBadge = Contrast.blend(pair.dark, over: 0x1C1C1E, opacity: 0.15)
            XCTAssertGreaterThanOrEqual(Contrast.ratio(pair.light, lightBadge), 4.5, "\(name) badge, light")
            XCTAssertGreaterThanOrEqual(Contrast.ratio(pair.dark, darkBadge), 4.5, "\(name) badge, dark")
        }
    }

    /// Filled buttons: white on navy, and dark words on dark mode's sky blue.
    func testPrimaryButtonWordsAreReadable() {
        let accent = Theme.Pairs.accent, words = Theme.Pairs.onAccent
        XCTAssertGreaterThanOrEqual(Contrast.ratio(words.light, accent.light), 4.5)
        XCTAssertGreaterThanOrEqual(Contrast.ratio(words.dark, accent.dark), 4.5)
        // The reason for onAccent: white on sky blue is far too faint.
        XCTAssertLessThan(Contrast.ratio(0xFFFFFF, accent.dark), 3)
    }

    func testContrastMath() {
        XCTAssertEqual(Contrast.ratio(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(Contrast.ratio(0x777777, 0x777777), 1, accuracy: 0.001)
        XCTAssertEqual(Contrast.blend(0x000000, over: 0xFFFFFF, opacity: 0.5), 0x808080)
    }

    func testWelcomeShowsOnlyOnANewInstall() {
        XCTAssertTrue(Welcome.shouldShow(hasSeen: false, hasPeople: false))
        XCTAssertFalse(Welcome.shouldShow(hasSeen: true, hasPeople: false))
        // Someone who had the app before this screen existed goes straight to their records.
        XCTAssertFalse(Welcome.shouldShow(hasSeen: false, hasPeople: true))
    }
}
