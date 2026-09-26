// Entry.swift
// budget. — eine erfasste Buchung
//
// Eine Buchung entsteht durch Tippen oder durch den Import des Trade-Republic-
// Exports. Der Kern ist derselbe wie immer: Betrag, Richtung, Kategorie, Tag. Was
// der Import zusätzlich weiß — Händler, MCC, Gegenkonto, die Transaktions-ID —
// hängt als optionale Felder daran und fehlt bei Buchungen von Hand einfach.

import Foundation

/// Geld rein, Geld raus, Geld ins Depot. Die Richtung hängt an der Buchung *und* an
/// der Kategorie — „Gehalt" soll beim Erfassen einer Ausgabe gar nicht erst auftauchen.
nonisolated enum Direction: String, Codable, Hashable, Sendable, CaseIterable {
    case expense
    case income
    case invest

    /// Einzahl, für Knöpfe: „Ausgabe"
    var label: String {
        switch self {
        case .expense: return "Ausgabe"
        case .income: return "Einnahme"
        case .invest: return "Investition"
        }
    }

    /// Mehrzahl, für Summen und Listen: „Ausgaben"
    var plural: String {
        switch self {
        case .expense: return "Ausgaben"
        case .income: return "Einnahmen"
        case .invest: return "Investiert"
        }
    }

    var opposite: Direction { self == .income ? .expense : .income }

    /// Verlässt das Geld das Konto? Ausgaben und Investitionen ja, Einnahmen nein.
    var isOutflow: Bool { self != .income }

    /// Die Seiten, die zu einem Geldfluss passen: Was rausging, kann Ausgabe oder
    /// Investition sein, was reinkam, nur Einnahme. Alles andere wird gar nicht
    /// erst angeboten.
    static func compatible(withInflow inflow: Bool) -> [Direction] {
        inflow ? [.income] : [.expense, .invest]
    }

    static func compatible(with direction: Direction) -> [Direction] {
        compatible(withInflow: !direction.isOutflow)
    }
}

/// Damit eine Richtung selbst ein Blatt auslösen kann (`sheet(item:)`).
nonisolated extension Direction: Identifiable {
    var id: String { rawValue }
}

/// Woher eine Buchung kommt.
nonisolated enum EntrySource: String, Codable, Hashable, Sendable {
    case manual
    case tradeRepublic
}

/// Ob eine Buchung zählt — und wie.
nonisolated enum EntryKind: String, Codable, Hashable, Sendable {
    /// Zählt in Ringe und Blasen.
    case flow
    /// Geld zwischen eigenen Konten. Zählt nirgends.
    case transfer
    /// Geld kommt zurück: senkt die Kategorie der ursprünglichen Buchung, statt als
    /// Einnahme zu gelten.
    case refund
}

/// Ob der Nutzer die Buchung so gewollt hat.
nonisolated enum EntryStatus: String, Codable, Hashable, Sendable {
    /// Von Hand erfasst oder ausdrücklich bestätigt.
    case confirmed
    /// Vorschlag der Maschine, wartet im Posteingang. Zählt nicht.
    case proposed
    /// Von der Maschine gebucht, weil sie sich sicher war. Zählt, ist aber markiert.
    case autoBooked
}

/// Eine Buchung.
///
/// `amount` ist immer positiv — das Vorzeichen steckt in `direction`. So kann eine
/// Zahl beim Eintippen nie „aus Versehen" die Seite wechseln, und die Ringe müssen
/// keine negativen Winkel kennen.
nonisolated struct Entry: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var date: CalendarDate
    var amount: Decimal
    var direction: Direction
    var categoryID: UUID
    var note: String
    /// Nur zum stabilen Sortieren innerhalb eines Tages — zwei Buchungen am selben
    /// Tag sollen in der Reihenfolge stehen, in der sie erfasst wurden.
    let createdAt: Date

    var source: EntrySource
    /// Die `transaction_id` aus dem Export. Der Schlüssel gegen Dopplungen.
    var externalID: String?
    /// Der Händler, wie die Quelle ihn nennt — roh, für das Lernen.
    var merchant: String?
    var mcc: String?
    var counterpartyIBAN: String?
    var isin: String?
    /// Der `type` aus dem Export, für Erklärungen und das Lernen je Typ.
    var importType: String?
    var kind: EntryKind
    var status: EntryStatus
    /// Erstattung: die Buchung, die sie senkt.
    var refundOf: UUID?
    /// Saveback: Gutschrift und der Kauf, den sie finanziert, zeigen aufeinander.
    var pairedWith: UUID?
    /// Was die Maschine meinte — bleibt auch nach der Entscheidung stehen, damit sich
    /// nachvollziehen lässt, warum eine Buchung so gelandet ist.
    var suggestion: Suggestion?

    init(
        id: UUID = UUID(),
        date: CalendarDate = .today(),
        amount: Decimal,
        direction: Direction,
        categoryID: UUID,
        note: String = "",
        createdAt: Date = Date(),
        source: EntrySource = .manual,
        externalID: String? = nil,
        merchant: String? = nil,
        mcc: String? = nil,
        counterpartyIBAN: String? = nil,
        isin: String? = nil,
        importType: String? = nil,
        kind: EntryKind = .flow,
        status: EntryStatus = .confirmed,
        refundOf: UUID? = nil,
        pairedWith: UUID? = nil,
        suggestion: Suggestion? = nil
    ) {
        self.id = id
        self.date = date
        self.amount = max(0, amount)
        self.direction = direction
        self.categoryID = categoryID
        self.note = note
        self.createdAt = createdAt
        self.source = source
        self.externalID = externalID
        self.merchant = merchant
        self.mcc = mcc
        self.counterpartyIBAN = counterpartyIBAN
        self.isin = isin
        self.importType = importType
        self.kind = kind
        self.status = status
        self.refundOf = refundOf
        self.pairedWith = pairedWith
        self.suggestion = suggestion
    }

    var month: YearMonth { date.yearMonth }

    /// Vorzeichenbehaftet, aus Sicht des Kontos: Was reinkommt ist positiv.
    /// Eine Erstattung dreht das Vorzeichen ihrer Richtung um.
    var signedAmount: Decimal {
        let base = direction == .income ? amount : -amount
        return kind == .refund ? -base : base
    }

    /// Zählt die Buchung in Summen und Blasen?
    var counts: Bool { status != .proposed && kind != .transfer }

    /// Kam das Geld rein? Bei Erstattungen ja, obwohl sie auf der Ausgabenseite stehen.
    var isInflow: Bool { signedAmount > 0 }
    /// Die Seiten, die für diese Buchung überhaupt in Frage kommen.
    var compatibleDirections: [Direction] { Direction.compatible(withInflow: isInflow) }

    /// Der Name, unter dem die Buchung in Listen steht: Notiz, sonst Händler.
    var title: String {
        if !note.isEmpty { return note }
        if let merchant { return MerchantKey.displayName(merchant) }
        return ""
    }

    /// Die Signale, aus denen gelernt wird.
    var signals: Signals {
        Signals(
            merchantKey: merchant.flatMap(MerchantKey.normalized),
            tokens: merchant.map(MerchantKey.tokens) ?? [],
            mcc: mcc,
            iban: counterpartyIBAN,
            isin: isin,
            // Nur Typen mit eigener Bedeutung (Zinsen, Sparplan …) taugen zum Lernen —
            // „Kartenzahlung" sagt nichts darüber, wofür das Geld war.
            importType: SuggestionEngine.typePrior(importType) != nil ? importType : nil)
    }

    // MARK: - Codable, von Hand

    private enum CodingKeys: String, CodingKey {
        case id, date, amount, direction, categoryID, note, createdAt
        case source, externalID, merchant, mcc, counterpartyIBAN, isin, importType
        case kind, status, refundOf, pairedWith, suggestion
    }

    /// Von Hand, damit eine Datei aus Schema 2 — ohne die neuen Felder — lesbar
    /// bleibt und als Buchung von Hand gilt.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(CalendarDate.self, forKey: .date)
        amount = max(0, try c.decode(Decimal.self, forKey: .amount))
        direction = try c.decode(Direction.self, forKey: .direction)
        categoryID = try c.decode(UUID.self, forKey: .categoryID)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        source = try c.decodeIfPresent(EntrySource.self, forKey: .source) ?? .manual
        externalID = try c.decodeIfPresent(String.self, forKey: .externalID)
        merchant = try c.decodeIfPresent(String.self, forKey: .merchant)
        mcc = try c.decodeIfPresent(String.self, forKey: .mcc)
        counterpartyIBAN = try c.decodeIfPresent(String.self, forKey: .counterpartyIBAN)
        isin = try c.decodeIfPresent(String.self, forKey: .isin)
        importType = try c.decodeIfPresent(String.self, forKey: .importType)
        kind = try c.decodeIfPresent(EntryKind.self, forKey: .kind) ?? .flow
        status = try c.decodeIfPresent(EntryStatus.self, forKey: .status) ?? .confirmed
        refundOf = try c.decodeIfPresent(UUID.self, forKey: .refundOf)
        pairedWith = try c.decodeIfPresent(UUID.self, forKey: .pairedWith)
        suggestion = try c.decodeIfPresent(Suggestion.self, forKey: .suggestion)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(amount, forKey: .amount)
        try c.encode(direction, forKey: .direction)
        try c.encode(categoryID, forKey: .categoryID)
        try c.encode(note, forKey: .note)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(externalID, forKey: .externalID)
        try c.encodeIfPresent(merchant, forKey: .merchant)
        try c.encodeIfPresent(mcc, forKey: .mcc)
        try c.encodeIfPresent(counterpartyIBAN, forKey: .counterpartyIBAN)
        try c.encodeIfPresent(isin, forKey: .isin)
        try c.encodeIfPresent(importType, forKey: .importType)
        try c.encode(kind, forKey: .kind)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(refundOf, forKey: .refundOf)
        try c.encodeIfPresent(pairedWith, forKey: .pairedWith)
        try c.encodeIfPresent(suggestion, forKey: .suggestion)
    }
}

nonisolated extension Decimal {
    /// Passen zwei Beträge zusammen? Wer 35 € auslegt und 35,50 € zurückbekommt, hat
    /// einen Ausgleich, keinen Sonderfall: bis 1 € oder 5 % Unterschied gelten als gleich.
    func roughlyEquals(_ other: Decimal) -> Bool {
        let difference = abs(self - other)
        let tolerance = max(Decimal(1), min(self, other) * Decimal(string: "0.05")!)
        return difference <= tolerance
    }
}

nonisolated extension BudgetCategory {
    /// Die „Kategorie" einer Umbuchung: keine. Umbuchungen tauchen in keinem Ring
    /// und keiner Blase auf, brauchen aber einen Wert im Feld.
    static let noneID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
