// MerchantMemory.swift
// budget. — was der Nutzer der App beigebracht hat
//
// Eine Tabelle mit Zählungen, keine Modellgewichte. Je Signal (Händler, Wort,
// MCC, Gegenkonto, Wertpapier, Buchungstyp) steht, wie oft welche Kategorie
// bestätigt und wie oft sie abgelehnt wurde. Mehr braucht ein Vorschlag nicht,
// um erklärbar zu bleiben: „EDEKA 7× als Lebensmittel bestätigt".

import Foundation

nonisolated struct Tally: Codable, Hashable, Sendable {
    var confirmed: Int
    var rejected: Int
    var lastAt: Date

    /// Was von der Zählung übrig bleibt: Ablehnungen wiegen doppelt, und was älter
    /// als ein Jahr ist, zählt halb — wer seine Kategorien umbaut, wird nicht ewig
    /// von alten Entscheidungen verfolgt.
    func weight(now: Date) -> Double {
        let raw = Double(confirmed) - 2 * Double(rejected)
        guard raw > 0 else { return 0 }
        let age = now.timeIntervalSince(lastAt)
        return age > 365 * 24 * 3600 ? raw / 2 : raw
    }
}

/// Die Signale einer Buchung, aus denen gelernt und vorgeschlagen wird.
nonisolated struct Signals: Hashable, Sendable {
    var merchantKey: String?
    var tokens: [String] = []
    var mcc: String?
    var iban: String?
    var isin: String?
    var importType: String?
    /// Nur bei Menschen: Name und Betrag zusammen — „Mutter, 200 €". Der Name allein
    /// darf nichts entscheiden, der immer gleiche Betrag derselben Person schon.
    var personAmount: String?
}

nonisolated struct MerchantMemory: Codable, Hashable, Sendable {
    /// Schlüssel → Kategorie (als String, damit JSON ein Objekt schreibt) → Zählung.
    var byMerchant: [String: [String: Tally]]
    var byToken: [String: [String: Tally]]
    var byMCC: [String: [String: Tally]]
    var byIBAN: [String: [String: Tally]]
    var byISIN: [String: [String: Tally]]
    var byType: [String: [String: Tally]]
    var byPersonAmount: [String: [String: Tally]]

    init(
        byMerchant: [String: [String: Tally]] = [:],
        byToken: [String: [String: Tally]] = [:],
        byMCC: [String: [String: Tally]] = [:],
        byIBAN: [String: [String: Tally]] = [:],
        byISIN: [String: [String: Tally]] = [:],
        byType: [String: [String: Tally]] = [:],
        byPersonAmount: [String: [String: Tally]] = [:]
    ) {
        self.byMerchant = byMerchant
        self.byToken = byToken
        self.byMCC = byMCC
        self.byIBAN = byIBAN
        self.byISIN = byISIN
        self.byType = byType
        self.byPersonAmount = byPersonAmount
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        byMerchant = try c.decodeIfPresent([String: [String: Tally]].self, forKey: .byMerchant) ?? [:]
        byToken = try c.decodeIfPresent([String: [String: Tally]].self, forKey: .byToken) ?? [:]
        byMCC = try c.decodeIfPresent([String: [String: Tally]].self, forKey: .byMCC) ?? [:]
        byIBAN = try c.decodeIfPresent([String: [String: Tally]].self, forKey: .byIBAN) ?? [:]
        byISIN = try c.decodeIfPresent([String: [String: Tally]].self, forKey: .byISIN) ?? [:]
        byType = try c.decodeIfPresent([String: [String: Tally]].self, forKey: .byType) ?? [:]
        byPersonAmount = try c.decodeIfPresent([String: [String: Tally]].self, forKey: .byPersonAmount) ?? [:]
    }

    var isEmpty: Bool {
        byMerchant.isEmpty && byToken.isEmpty && byMCC.isEmpty
            && byIBAN.isEmpty && byISIN.isEmpty && byType.isEmpty && byPersonAmount.isEmpty
    }

    // MARK: - Lernen

    /// Eine Entscheidung für diese Kategorie, auf allen Signalen der Buchung.
    mutating func confirm(_ signals: Signals, as category: UUID, at now: Date = Date()) {
        apply(signals, category: category, confirmed: 1, rejected: 0, now: now)
    }

    /// Eine Entscheidung gegen diese Kategorie.
    mutating func reject(_ signals: Signals, as category: UUID, at now: Date = Date()) {
        apply(signals, category: category, confirmed: 0, rejected: 1, now: now)
    }

    /// Eine Korrektur ist beides: gegen den Vorschlag, für die Wahl.
    mutating func correct(
        _ signals: Signals, from proposed: UUID, to chosen: UUID, at now: Date = Date()
    ) {
        if proposed != chosen { reject(signals, as: proposed, at: now) }
        confirm(signals, as: chosen, at: now)
    }

    /// Eine gelöschte Kategorie darf nirgends mehr vorgeschlagen werden.
    mutating func forget(category: UUID) {
        let key = category.uuidString
        func purge(_ table: inout [String: [String: Tally]]) {
            for (k, tallies) in table {
                var kept = tallies
                kept[key] = nil
                if kept.isEmpty { table[k] = nil } else { table[k] = kept }
            }
        }
        purge(&byMerchant); purge(&byToken); purge(&byMCC)
        purge(&byIBAN); purge(&byISIN); purge(&byType); purge(&byPersonAmount)
    }

    private mutating func apply(
        _ signals: Signals, category: UUID, confirmed: Int, rejected: Int, now: Date
    ) {
        let key = category.uuidString
        func bump(_ table: inout [String: [String: Tally]], _ signal: String?) {
            guard let signal, !signal.isEmpty else { return }
            var tallies = table[signal] ?? [:]
            var tally = tallies[key] ?? Tally(confirmed: 0, rejected: 0, lastAt: now)
            tally.confirmed += confirmed
            tally.rejected += rejected
            tally.lastAt = now
            tallies[key] = tally
            table[signal] = tallies
        }
        bump(&byMerchant, signals.merchantKey)
        for token in signals.tokens { bump(&byToken, token) }
        bump(&byMCC, signals.mcc)
        bump(&byIBAN, signals.iban)
        bump(&byISIN, signals.isin)
        bump(&byType, signals.importType)
        bump(&byPersonAmount, signals.personAmount)
    }

    // MARK: - Nachschlagen

    /// Gewichtete Zählungen je Kategorie für ein Signal.
    static func weights(_ tallies: [String: Tally]?, now: Date) -> [UUID: Double] {
        guard let tallies else { return [:] }
        var result: [UUID: Double] = [:]
        for (key, tally) in tallies {
            guard let id = UUID(uuidString: key) else { continue }
            let weight = tally.weight(now: now)
            if weight > 0 { result[id] = weight }
        }
        return result
    }

    /// Die Kategorie, die für diesen Händler am häufigsten bestätigt wurde.
    func topCategory(forMerchant merchant: String, now: Date = Date()) -> UUID? {
        guard let key = MerchantKey.normalized(merchant) else { return nil }
        return Self.weights(byMerchant[key], now: now).max { $0.value < $1.value }?.key
    }

    /// Person und Betrag: die Kategorie mit den meisten Bestätigungen und deren Zahl.
    func personAmountRule(_ key: String?, now: Date = Date()) -> (category: UUID, count: Int)? {
        guard let key else { return nil }
        let weights = Self.weights(byPersonAmount[key], now: now).sorted { $0.value > $1.value }
        guard let best = weights.first else { return nil }
        let runnerUp = weights.count > 1 ? weights[1].value : 0
        let net = Int((best.value - runnerUp).rounded())
        return net >= 1 ? (best.key, net) : nil
    }

    /// Wie oft ein Händler netto auf diese Kategorie bestätigt wurde.
    func confirmations(merchantKey: String?, category: UUID) -> Int {
        guard let merchantKey, let tally = byMerchant[merchantKey]?[category.uuidString]
        else { return 0 }
        return max(0, tally.confirmed - 2 * tally.rejected)
    }
}
