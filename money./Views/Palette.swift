import SwiftUI

/// The whole colour system. Two values per token, light and dark, resolved by UIKit so no
/// view has to know which appearance it is in.
///
/// Deliberately achromatic: one muted navy carries every accent, and the only other colour
/// in the app is the overspend red. Nothing is a gradient.
enum Palette {
    static let canvas = Color(light: 0xF2F2F2, dark: 0x0F1011)
    static let card = Color(light: 0xFFFFFF, dark: 0x1A1B1E)
    static let ink = Color(light: 0x1D2630, dark: 0xF2F2F2)

    /// Secondary text. #8A9099 from the palette pick only reaches ~3:1 on white, which is
    /// under AA at footnote size, so the text tone is darkened and the lighter grey lives
    /// on as `faint` for decoration.
    static let muted = Color(light: 0x6B7280, dark: 0x9BA1AA)
    static let faint = Color(light: 0x9CA3AE, dark: 0x71767E)

    static let hairline = Color(light: 0xE6E6E8, dark: 0x26272B)
    static let track = Color(light: 0xE9E9EB, dark: 0x2B2D31)
    static let chip = Color(light: 0xEAEAEC, dark: 0x222327)

    /// The navy lightens on dark — the same hue would disappear into the card.
    static let accent = Color(light: 0x3A4766, dark: 0x8FA3BF)
    static let warn = Color(light: 0xB3453F, dark: 0xC4615A)

    static let cardShadow = Color(light: 0x616E7C, dark: 0x000000)
    static let cardShadowOpacity = ColorSchemeValue(light: 0.10, dark: 0.35)
}

/// A plain light/dark pair for values that are not colours.
struct ColorSchemeValue {
    let light: Double
    let dark: Double

    func callAsFunction(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? dark : light
    }
}

extension Color {
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
            alpha: 1)
    }
}

enum Metrics {
    static let cardRadius: CGFloat = 18
    static let cardPadding: CGFloat = 16
    static let sectionGap: CGFloat = 26
    static let screenInset: CGFloat = 20
}
