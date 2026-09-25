// AppData.swift
// budget. — alles, was die App besitzt, in einem Codable-Wert

import Foundation

nonisolated struct ImportStamp: Codable, Hashable, Sendable {
    let date: Date
    let rows: Int
    let newestDate: CalendarDate
}

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

    /// Was der Nutzer der App beigebracht hat — je Händler, Wort, MCC, Konto, Papier.
    var memory: MerchantMemory

    /// Der Kontoinhaber, damit Überweisungen an sich selbst als Umbuchung gelten.
    var ownerName: String?
    /// IBANs eigener Konten bei anderen Banken.
    var ownIBANs: [String]
    /// Ab dieser Konfidenz bucht die Maschine selbst. 1 heißt: nie.
    var autoThreshold: Double
    /// Exportzeilen ohne Geld (Split, Steueroptimierung) und ausdrücklich verworfene —
    /// damit sie beim nächsten Import nicht wieder auftauchen.
    var ignoredExternalIDs: [String]
    var lastImport: ImportStamp?

    /// 1 war der CSV-Import mit Regeln und Klassifikator. 2 die reine Erfassung von
    /// Hand. 3 bringt den Import des Trade-Republic-Exports, drei Richtungen und das
    /// Gedächtnis mit Zählungen. Eine 2er-Datei wird gelesen und ergänzt.
    static let currentSchemaVersion = 3

    init(
        schemaVersion: Int = AppData.currentSchemaVersion,
        entries: [Entry] = [],
        categories: [BudgetCategory] = [],
        lastUsed: [String: UUID] = [:],
        memory: MerchantMemory = MerchantMemory(),
        ownerName: String? = nil,
        ownIBANs: [String] = [],
        autoThreshold: Double = 0.9,
        ignoredExternalIDs: [String] = [],
        lastImport: ImportStamp? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
        self.categories = categories
        self.lastUsed = lastUsed
        self.memory = memory
        self.ownerName = ownerName
        self.ownIBANs = ownIBANs
        self.autoThreshold = autoThreshold
        self.ignoredExternalIDs = ignoredExternalIDs
        self.lastImport = lastImport
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, entries, categories, lastUsed, memory
        case ownerName, ownIBANs, autoThreshold, ignoredExternalIDs, lastImport
        /// Nur zum Lesen von Schema 2.
        case merchantCategories
    }

    /// Von Hand geschrieben, damit ein neues Feld keine bestehende Datei unlesbar macht.
    ///
    /// Die synthetisierte Variante wirft bei einem fehlenden Schlüssel — eine Datei von
    /// gestern hätte die App also beim nächsten Update auf Anfang zurückgesetzt. Alles
    /// wird deshalb mit `decodeIfPresent` gelesen und fällt sonst auf den Standard.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? AppData.currentSchemaVersion

        // Schema 1 war der CSV-Import mit Klassifikator. Toleranz gegenüber fehlenden
        // Feldern darf nicht dazu führen, dass so eine Datei als leere App durchgeht.
        guard version >= 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container,
                debugDescription: "Schema \(version) kennt diese App nicht mehr.")
        }
        schemaVersion = AppData.currentSchemaVersion
        entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        categories = try container.decodeIfPresent([BudgetCategory].self, forKey: .categories) ?? []
        lastUsed = try container.decodeIfPresent([String: UUID].self, forKey: .lastUsed) ?? [:]
        var memory = try container.decodeIfPresent(MerchantMemory.self, forKey: .memory) ?? MerchantMemory()
        ownerName = try container.decodeIfPresent(String.self, forKey: .ownerName)
        ownIBANs = try container.decodeIfPresent([String].self, forKey: .ownIBANs) ?? []
        autoThreshold = try container.decodeIfPresent(Double.self, forKey: .autoThreshold) ?? 0.9
        ignoredExternalIDs = try container.decodeIfPresent([String].self, forKey: .ignoredExternalIDs) ?? []
        lastImport = try container.decodeIfPresent(ImportStamp.self, forKey: .lastImport)

        // Schema 2: Händler → eine Kategorie. Wird zu einer Bestätigung je Händler.
        if memory.isEmpty,
           let old = try container.decodeIfPresent([String: UUID].self, forKey: .merchantCategories) {
            let then = Date()
            for (merchant, category) in old {
                memory.confirm(Signals(merchantKey: merchant, tokens: MerchantKey.tokens(merchant)), as: category, at: then)
            }
        }
        self.memory = memory

        // Eine Datei aus Schema 2 kennt weder Investiert noch die neuen Bereiche.
        // Was der Seed inzwischen mitbringt und dem Namen nach fehlt, wird ergänzt —
        // einmal, beim Umstieg.
        if version < 3 {
            var next = (categories.map(\.sortIndex).max() ?? -1) + 1
            for seed in Seed.categories() where !categories.contains(where: {
                $0.direction == seed.direction
                    && $0.name.compare(seed.name, options: .caseInsensitive) == .orderedSame
            }) {
                var added = seed
                added.sortIndex = next
                next += 1
                categories.append(added)
            }
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(entries, forKey: .entries)
        try c.encode(categories, forKey: .categories)
        try c.encode(lastUsed, forKey: .lastUsed)
        try c.encode(memory, forKey: .memory)
        try c.encodeIfPresent(ownerName, forKey: .ownerName)
        try c.encode(ownIBANs, forKey: .ownIBANs)
        try c.encode(autoThreshold, forKey: .autoThreshold)
        try c.encode(ignoredExternalIDs, forKey: .ignoredExternalIDs)
        try c.encodeIfPresent(lastImport, forKey: .lastImport)
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

    /// Die Kategorie, die für diesen Händler am häufigsten bestätigt wurde — sofern
    /// es sie noch gibt.
    func rememberedCategory(forMerchant merchant: String) -> BudgetCategory? {
        category(memory.topCategory(forMerchant: merchant))
    }

    /// Vorauswahl für die Schnellerfassung: zuletzt benutzt, sonst die erste Kategorie
    /// dieser Richtung.
    func preferredCategory(for direction: Direction) -> BudgetCategory? {
        if let stored = category(lastUsed[direction.rawValue]), stored.direction == direction {
            return stored
        }
        return categories(for: direction).first
    }

    /// Was im Posteingang wartet, neueste zuerst.
    var proposals: [Entry] {
        entries.filter { $0.status == .proposed }
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }
}
