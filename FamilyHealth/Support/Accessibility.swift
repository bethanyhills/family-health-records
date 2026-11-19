import SwiftUI

/// A light and dark color kept as hex numbers, so tests can check their contrast.
struct ColorPair: Equatable {
    let light: UInt32
    let dark: UInt32

    var color: Color { Color(light: light, dark: dark) }
}

extension Theme {
    /// Colors for words, badges and small icons. Each one reads at 4.5:1 or better
    /// (the WCAG AA level for normal text) on white cards and on dark mode cells.
    enum Pairs {
        /// Same values as Theme.navy and the AccentColor asset.
        static let accent = ColorPair(light: 0x2B3F75, dark: 0x77A8F3)
        /// Words on a filled accent button: white on navy, dark navy on sky blue.
        static let onAccent = ColorPair(light: 0xFFFFFF, dark: 0x070A1F)
        static let danger = ColorPair(light: 0xB3261E, dark: 0xFF8A80)
        static let warning = ColorPair(light: 0x96500A, dark: 0xFFB259)
        static let caution = ColorPair(light: 0x735C00, dark: 0xF2D16B)
        static let success = ColorPair(light: 0x1A6E40, dark: 0x6FD69B)

        static let textColors: [(name: String, pair: ColorPair)] = [
            ("accent", accent), ("danger", danger), ("warning", warning),
            ("caution", caution), ("success", success),
        ]
    }

    /// What these colors sit on: white cards and the tinted page in light mode;
    /// grouped cells, the page and cards in dark mode.
    static let lightSurfaces: [UInt32] = [0xFFFFFF, 0xF4F6FB]
    static let darkSurfaces: [UInt32] = [0x1C1C1E, 0x070A1F, 0x141933]

    /// Errors and severe allergies.
    static let danger = Pairs.danger.color
    /// Warnings and moderate allergies.
    static let warning = Pairs.warning.color
    /// Mild allergies.
    static let caution = Pairs.caution.color
    /// Done, copied, unlocked.
    static let success = Pairs.success.color
    static let onAccent = Pairs.onAccent.color
}

/// WCAG contrast math, used by the tests that guard the palette.
enum Contrast {
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// From 1 (no contrast) to 21 (black on white).
    static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `color` laid over `background` at `opacity`, like a tinted badge.
    static func blend(_ color: UInt32, over background: UInt32, opacity: Double) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let top = Double((color >> UInt32(shift)) & 0xFF)
            let bottom = Double((background >> UInt32(shift)) & 0xFF)
            let mixed = UInt32((top * opacity + bottom * (1 - opacity)).rounded())
            return result | (mixed << UInt32(shift))
        }
    }
}

extension View {
    /// The main button on a screen. Dark mode's sky blue needs dark words;
    /// the usual white words on it are too faint to read.
    func primaryButton() -> some View {
        buttonStyle(.borderedProminent)
            .foregroundStyle(Theme.onAccent)
    }

    /// At least 44 by 44 points, Apple's smallest comfortable tap size.
    func minimumTapTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Side by side normally, stacked when someone uses one of the larger text sizes,
/// so nothing gets squeezed or cut off.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat?
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment: VerticalAlignment = .center
    @ViewBuilder let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: horizontalAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
        layout { content }
    }
}
