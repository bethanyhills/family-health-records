import SwiftUI
import UIKit

/// Binder Navy, the app's colors. Every color has a light and a dark version.
/// The main navy is also the app's AccentColor (Assets.xcassets), so buttons,
/// links, toggles and the "+" buttons pick it up without any code.
enum Theme {
    /// Main brand color: navy in light mode, sky blue in dark mode.
    static let navy = Color(light: 0x1F3A5F, dark: 0x8DB4E8)
    /// Second accent, like a binder's colored divider tab.
    static let amber = Color(light: 0xC9821E, dark: 0xF2C271)
    /// Screen background behind the white cards.
    static let background = Color(light: 0xF3F5F9, dark: 0x0D131C)
    /// Card background on screens that are not lists.
    static let card = Color(light: 0xFFFFFF, dark: 0x172131)

    /// Soft avatar colors, so family members are easy to tell apart.
    /// Each pair is (circle fill, initials color).
    static let avatarPalette: [(fill: Color, text: Color)] = [
        (Color(light: 0xDCE6F3, dark: 0x23385A), Color(light: 0x1F3A5F, dark: 0xA9C8F0)),
        (Color(light: 0xFBECD2, dark: 0x3D2F17), Color(light: 0x8A5A10, dark: 0xF2C271)),
        (Color(light: 0xDDEFE8, dark: 0x173A30), Color(light: 0x22664F, dark: 0x8FD3B8)),
        (Color(light: 0xF1E3F2, dark: 0x3A2340), Color(light: 0x7A3D82, dark: 0xDDB0E3)),
        (Color(light: 0xFCE3DD, dark: 0x40221C), Color(light: 0xA3402B, dark: 0xF39A85)),
        (Color(light: 0xE3EEFB, dark: 0x1D3350), Color(light: 0x2C5A96, dark: 0x8DB4E8)),
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
