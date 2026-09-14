// Palette.swift
// budget. — das ganze Farbsystem
//
// Zwei Werte pro Token, hell und dunkel, von UIKit aufgelöst — keine View muss
// wissen, in welchem Erscheinungsbild sie gerade steckt.
//
// Die Grundfläche bleibt achromatisch. Farbe tragen ausschließlich die Kategorien,
// und zwar in den Ringen und ihren Zeilen. Dadurch bedeutet Farbe in dieser App
// immer dasselbe: „das ist diese Kategorie".

import SwiftUI

enum Palette {
    static let canvas = Color(light: 0xF4F4F5, dark: 0x0E0F11)
    static let card = Color(light: 0xFFFFFF, dark: 0x17181B)
    /// Für Flächen, die auf einer Karte liegen — Chips, Tastenfelder.
    static let raised = Color(light: 0xEFEFF1, dark: 0x212327)
    static let ink = Color(light: 0x14181D, dark: 0xF4F4F5)

    static let muted = Color(light: 0x6B7280, dark: 0x9BA1AA)
    static let faint = Color(light: 0x9CA3AE, dark: 0x6E747C)

    static let hairline = Color(light: 0xE6E6E8, dark: 0x25272C)
    /// Die unsichtbare Bahn hinter einem Ring: da, wo nichts gebucht wurde.
    static let track = Color(light: 0xE7E7EA, dark: 0x1E2024)

    static let accent = Color(light: 0x3A4766, dark: 0x8FA3BF)

    /// Plus und Minus in der Ringmitte. Nicht als Kategorienfarbe verwendbar.
    static let positive = Color(light: 0x0E8F55, dark: 0x3DDC97)
    static let negative = Color(light: 0xD8434F, dark: 0xF6606B)

    static let cardShadow = Color(light: 0x616E7C, dark: 0x000000)
    static let cardShadowOpacity = ColorSchemeValue(light: 0.10, dark: 0.40)

    /// Die Farbe einer Kategorie. Ein unbekanntes Token — etwa aus einer Datei, die
    /// eine neuere Palette kannte — fällt auf Grau zurück, statt die Zeile zu verlieren.
    static func tint(_ tint: CategoryTint) -> Color {
        Palette.tints[tint.rawValue] ?? Palette.tints["slate"]!
    }

    private static let tints: [String: Color] = [
        "azure": Color(light: 0x0A84C8, dark: 0x2BB3F0),
        "coral": Color(light: 0xD8434F, dark: 0xF6606B),
        "indigo": Color(light: 0x4B3FD4, dark: 0x7B6CF6),
        "mint": Color(light: 0x0E8F55, dark: 0x3DDC97),
        "amber": Color(light: 0xB87A00, dark: 0xF5A623),
        "violet": Color(light: 0x8A33C8, dark: 0xBD7BF0),
        "rose": Color(light: 0xC72F76, dark: 0xF25FA8),
        "teal": Color(light: 0x0C8A88, dark: 0x2ED3CE),
        "lime": Color(light: 0x5B8C12, dark: 0x9BD84A),
        "sand": Color(light: 0x8E6A34, dark: 0xDCB273),
        "sky": Color(light: 0x2464CC, dark: 0x5FA5FA),
        "slate": Color(light: 0x58626F, dark: 0x94A3B4),
    ]
}

/// Ein einfaches Hell/Dunkel-Paar für Werte, die keine Farben sind.
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
    static let cardRadius: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let screenInset: CGFloat = 20
}
