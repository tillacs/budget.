// CategoryOptions.swift
// budget. — die Kategorienauswahl in der Einblendung des Kurzbefehls
//
// Bewusst eine Liste von Zeichenketten und keine `AppEntity`: Die Entity-Variante
// scheitert in der App-Intents-Laufzeit beim Zurückreichen der Auswahl
// („CategoryEntity is not a registered AppEntity identifier", auch im Release-Build).
// Gebraucht wird hier ohnehin nur eine Auswahlliste — kein Suchen, kein Verweisen,
// kein Weiterreichen an andere Aktionen.

import AppIntents
import Foundation

struct CategoryOptions: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [String] {
        let data = AppStore.shared.data
        return (data.categories(for: .expense) + data.categories(for: .income))
            .map(CategoryOptions.label)
    }

    /// „🍽️ Essen · Ausgabe" — das Zeichen zum Wiedererkennen, die Richtung, weil sie
    /// in einer gemischten Liste das Einzige ist, was man der Kategorie nicht ansieht.
    static func label(_ category: BudgetCategory) -> String {
        "\(category.symbol) \(category.name) · \(category.direction.label)"
    }

    /// Zurück zur Kategorie: zuerst über die vollständige Beschriftung, dann über den
    /// blanken Namen — damit auch „Essen" trifft, wenn jemand den Kurzbefehl mit
    /// eigenem Text füttert oder die Kategorie inzwischen umbenannt wurde.
    @MainActor
    static func category(for label: String) -> BudgetCategory? {
        let all = AppStore.shared.data.categories
        if let exact = all.first(where: { CategoryOptions.label($0) == label }) { return exact }

        let bare = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.first { $0.name.lowercased() == bare }
    }
}
