// BudgetCategory.swift
// budget. — die Kategorien, die der Nutzer selbst anlegt
//
// Es gibt keine mitgelieferte Kategorien-Logik mehr, keine Regeln, keinen Klassifikator.
// Eine Kategorie ist ein Name, ein Zeichen, eine Farbe — mehr braucht ein Ringsegment nicht.

import Foundation

/// Der Farbton eines Ringsegments.
///
/// Als String-Token und nicht als `enum` gespeichert: Wenn die Palette später wächst
/// oder umbenannt wird, soll eine alte Datei nicht als Ganzes unlesbar werden. Ein
/// unbekannter Ton fällt in der Darstellung auf `.slate` zurück.
nonisolated struct CategoryTint: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let azure = CategoryTint(rawValue: "azure")
    static let coral = CategoryTint(rawValue: "coral")
    static let indigo = CategoryTint(rawValue: "indigo")
    static let mint = CategoryTint(rawValue: "mint")
    static let amber = CategoryTint(rawValue: "amber")
    static let violet = CategoryTint(rawValue: "violet")
    static let rose = CategoryTint(rawValue: "rose")
    static let teal = CategoryTint(rawValue: "teal")
    static let lime = CategoryTint(rawValue: "lime")
    static let sand = CategoryTint(rawValue: "sand")
    static let sky = CategoryTint(rawValue: "sky")
    static let slate = CategoryTint(rawValue: "slate")

    /// Reihenfolge der Auswahl im Editor — bewusst so sortiert, dass zwei benachbarte
    /// Töne nie verwechselbar sind, wenn man sie nacheinander vergibt.
    static let all: [CategoryTint] = [
        .azure, .coral, .mint, .violet, .amber, .indigo,
        .rose, .teal, .lime, .sky, .sand, .slate,
    ]
}

nonisolated struct BudgetCategory: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    /// Ein Emoji. Kein SF Symbol: Der Nutzer legt die Kategorien selbst an, und die
    /// Emoji-Tastatur ist der einzige Symbolwähler, den jeder schon bedienen kann.
    var symbol: String
    var tint: CategoryTint
    var direction: Direction
    var sortIndex: Int

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "•",
        tint: CategoryTint = .slate,
        direction: Direction = .expense,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.tint = tint
        self.direction = direction
        self.sortIndex = sortIndex
    }
}
