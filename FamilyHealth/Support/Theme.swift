import SwiftUI
import UIKit

/// The app's colors, taken from the Health Binder logo: a deep navy, the logo's
/// light blue tabs and its red. Every color has a light and a dark version.
/// The main navy is also the app's AccentColor (Assets.xcassets), so buttons,
/// links, toggles and the "+" buttons pick it up without any code.
enum Theme {
    /// Main brand color: logo navy in light mode, the logo's light blue in dark mode.
    static let navy = Color(light: 0x2B3F75, dark: 0x77A8F3)
    /// The logo's red. For the logo and small marks, not for words.
    static let red = Color(light: 0xEB473B, dark: 0xF0685D)
    /// Screen background behind the white cards.
    static let background = Color(light: 0xF4F6FB, dark: 0x070A1F)
    /// Card background on screens that are not lists.
    static let card = Color(light: 0xFFFFFF, dark: 0x141933)

    /// Soft avatar colors, so family members are easy to tell apart.
    /// Each pair is (circle fill, initials color).
    static let avatarPalette: [(fill: Color, text: Color)] = [
        (Color(light: 0xDCE6F8, dark: 0x1E2C55), Color(light: 0x2B3F75, dark: 0xA9C8F5)),
        (Color(light: 0xFCE1DE, dark: 0x3F1A17), Color(light: 0xB0322A, dark: 0xFF9A90)),
        (Color(light: 0xDDEFE8, dark: 0x173A30), Color(light: 0x22664F, dark: 0x8FD3B8)),
        (Color(light: 0xEDE4F7, dark: 0x2E2346), Color(light: 0x5B3E8F, dark: 0xCDB6F0)),
        (Color(light: 0xFBECD2, dark: 0x3D2F17), Color(light: 0x8A5A10, dark: 0xF2C271)),
        (Color(light: 0xE1F0FB, dark: 0x16324A), Color(light: 0x245E8A, dark: 0x8CC6F0)),
    ]

    /// The same person always gets the same color, based on their initials.
    static func avatarColors(for initials: String) -> (fill: Color, text: Color) {
        let sum = initials.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return avatarPalette[sum % avatarPalette.count]
    }
}

/// The app icon, drawn inside the app (lock cover, unlock sheet).
struct BrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        Image("BrandMark")
            .resizable()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension Color {
    /// A color that switches between two hex values for light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// Tinted screen background with white cards, used on every list and form.
    func brandedBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}
