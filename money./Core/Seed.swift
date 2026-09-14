// Seed.swift
// budget. — womit die App beim ersten Start dasteht
//
// Der Nutzer legt seine Kategorien selbst an. Ein komplett leeres Raster wäre beim
// ersten Doppeltipp auf die Rückseite aber eine Sackgasse, also stehen ein paar
// gängige da — jede einzelne umbenennbar, umfärbbar, löschbar.

import Foundation

nonisolated enum Seed {
    static func categories() -> [BudgetCategory] {
        var index = 0
        func next() -> Int { defer { index += 1 }; return index }

        return [
            BudgetCategory(name: "Essen", symbol: "🍽️", tint: .azure, direction: .expense, sortIndex: next()),
            BudgetCategory(name: "Lebensmittel", symbol: "🛒", tint: .coral, direction: .expense, sortIndex: next()),
            BudgetCategory(name: "Wohnen", symbol: "🏠", tint: .indigo, direction: .expense, sortIndex: next()),
            BudgetCategory(name: "Unterwegs", symbol: "🚆", tint: .amber, direction: .expense, sortIndex: next()),
            BudgetCategory(name: "Freizeit", symbol: "🎧", tint: .violet, direction: .expense, sortIndex: next()),
            BudgetCategory(name: "Abos", symbol: "🔁", tint: .teal, direction: .expense, sortIndex: next()),
            BudgetCategory(name: "Gehalt", symbol: "💼", tint: .mint, direction: .income, sortIndex: next()),
            BudgetCategory(name: "Sonstiges", symbol: "✨", tint: .sky, direction: .income, sortIndex: next()),
        ]
    }
}
