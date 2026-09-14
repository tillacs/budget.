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

    /// Händler → Kategorie, vom Nutzer selbst gefüllt: Jede bestätigte Buchung, die
    /// einen Händler oder eine Notiz nennt, legt hier ihre Kategorie ab. Beim nächsten
    /// Mal steht sie im Vorschlag schon drin.
    ///
    /// Der Schlüssel ist der normalisierte Händler (siehe `MerchantKey`).
    var merchantCategories: [String: UUID]

    /// 1 war der CSV-Import mit Regeln und Klassifikator. Version 2 hat damit nichts
    /// mehr gemeinsam; eine alte Datei wird nicht migriert, sondern verworfen.
    static let currentSchemaVersion = 2

    init(
        schemaVersion: Int = AppData.currentSchemaVersion,
        entries: [Entry] = [],
        categories: [BudgetCategory] = [],
        lastUsed: [String: UUID] = [:],
        merchantCategories: [String: UUID] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
        self.categories = categories
        self.lastUsed = lastUsed
        self.merchantCategories = merchantCategories
    }

    /// Von Hand geschrieben, damit ein neues Feld keine bestehende Datei unlesbar macht.
    ///
    /// Die synthetisierte Variante wirft bei einem fehlenden Schlüssel — eine Datei von
    /// gestern hätte die App also beim nächsten Update auf Anfang zurückgesetzt. Alles
    /// wird deshalb mit `decodeIfPresent` gelesen und fällt sonst auf den Standard.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? AppData.currentSchemaVersion

        // Schema 1 war der CSV-Import. Toleranz gegenüber fehlenden Feldern darf nicht
        // dazu führen, dass so eine Datei als leere App durchgeht — sie wird abgelehnt
        // und damit verworfen, statt den Nutzer vor eine App ohne Kategorien zu setzen.
        guard schemaVersion >= 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container,
                debugDescription: "Schema \(schemaVersion) kennt diese App nicht mehr.")
        }
        entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        categories = try container.decodeIfPresent([BudgetCategory].self, forKey: .categories) ?? []
        lastUsed = try container.decodeIfPresent([String: UUID].self, forKey: .lastUsed) ?? [:]
        merchantCategories = try container
            .decodeIfPresent([String: UUID].self, forKey: .merchantCategories) ?? [:]
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

    /// Die Kategorie, die für diesen Händler zuletzt bestätigt wurde — sofern es sie
    /// noch gibt.
    func rememberedCategory(forMerchant merchant: String) -> BudgetCategory? {
        guard let key = MerchantKey.normalized(merchant) else { return nil }
        return category(merchantCategories[key])
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
