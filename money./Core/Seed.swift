// Seed.swift
// budget. — womit die App beim ersten Start dasteht
//
// Der Nutzer legt seine Kategorien selbst an. Ein komplett leeres Raster wäre beim
// ersten Doppeltipp auf die Rückseite aber eine Sackgasse, also stehen ein paar
// gängige da — jede einzelne umbenennbar, umfärbbar, löschbar. Die Namen sind
// zugleich die, auf die die Vorbelegung nach Händlercode zeigt.

import Foundation

nonisolated enum Seed {
    static func categories() -> [BudgetCategory] {
        var index = 0
        func next() -> Int { defer { index += 1 }; return index }
        func make(_ name: String, _ symbol: String, _ tint: CategoryTint, _ direction: Direction) -> BudgetCategory {
            BudgetCategory(name: name, symbol: symbol, tint: tint, direction: direction, sortIndex: next())
        }

        return [
            make("Essen", "🍽️", .azure, .expense),
            make("Lebensmittel", "🛒", .coral, .expense),
            make("Wohnen", "🏠", .indigo, .expense),
            make("Unterwegs", "🚆", .amber, .expense),
            make("Freizeit", "🎧", .violet, .expense),
            make("Abos", "🔁", .teal, .expense),
            make("Shopping", "🛍️", .rose, .expense),
            make("Drogerie", "🧴", .lime, .expense),
            make("Gesundheit", "💊", .sky, .expense),
            make("Bargeld", "💶", .sand, .expense),
            make("Gehalt", "💼", .mint, .income),
            make("Kapitalerträge", "💹", .teal, .income),
            make("Saveback", "🎁", .rose, .income),
            make("Sonstiges", "✨", .sky, .income),
            make("Sparplan", "📈", .indigo, .invest),
            make("Einzelkauf", "🧾", .sand, .invest),
            make("Saveback", "🎁", .rose, .invest),
        ]
    }
}
