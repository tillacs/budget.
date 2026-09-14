// AppData.swift
// budget. — alles, was die App besitzt, in einem Codable-Wert

import Foundation

nonisolated struct AppData: Codable, Sendable {
    var schemaVersion: Int
    var entries: [Entry]
    var categories: [BudgetCategory]
    /// Zuletzt benutzte Kategorie je Richtung, als Rohwert der Richtung abgelegt,
    /// damit das Dictionary als JSON-Objekt und nicht als Array kodiert wird.
    ///
    /// Das ist kein Komfort-Detail, sondern der Kern der Schnellerfassung: Nach dem
    /// Doppeltipp auf die Rückseite steht die wahrscheinlichste Kategorie schon da,
    /// und es bleiben drei Ziffern bis zum Sichern.
    var lastUsed: [String: UUID]

    /// 1 war der CSV-Import mit Regeln und Klassifikator. Version 2 hat damit nichts
    /// mehr gemeinsam; eine alte Datei wird nicht migriert, sondern verworfen.
    static let currentSchemaVersion = 2

    init(
        schemaVersion: Int = AppData.currentSchemaVersion,
        entries: [Entry] = [],
        categories: [BudgetCategory] = [],
        lastUsed: [String: UUID] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
        self.categories = categories
        self.lastUsed = lastUsed
    }

    static func seeded() -> AppData {
        AppData(categories: Seed.categories())
    }

    func categories(for direction: Direction) -> [BudgetCategory] {
        categories
            .filter { $0.direction == direction }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func category(_ id: UUID?) -> BudgetCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    /// Vorauswahl für die Schnellerfassung: zuletzt benutzt, sonst die erste Kategorie
    /// dieser Richtung.
    func preferredCategory(for direction: Direction) -> BudgetCategory? {
        if let stored = category(lastUsed[direction.rawValue]), stored.direction == direction {
            return stored
        }
        return categories(for: direction).first
    }
}
