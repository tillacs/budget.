// Entry.swift
// budget. — eine erfasste Buchung
//
// Alles in dieser App entsteht durch Tippen, nicht durch Import. Eine Buchung ist
// deshalb so klein wie möglich: Betrag, Richtung, Kategorie, Tag. Mehr will man
// zwei Sekunden nach dem Doppeltipp auf die Rückseite nicht eingeben.

import Foundation

/// Geld rein oder Geld raus. Die Richtung hängt an der Buchung *und* an der
/// Kategorie — „Gehalt" soll beim Erfassen einer Ausgabe gar nicht erst auftauchen.
nonisolated enum Direction: String, Codable, Hashable, Sendable, CaseIterable {
    case expense
    case income

    /// Einzahl, für Knöpfe: „Ausgabe"
    var label: String {
        switch self {
        case .expense: return "Ausgabe"
        case .income: return "Einnahme"
        }
    }

    /// Mehrzahl, für Summen und Listen: „Ausgaben"
    var plural: String {
        switch self {
        case .expense: return "Ausgaben"
        case .income: return "Einnahmen"
        }
    }

    var opposite: Direction { self == .expense ? .income : .expense }
}

/// Damit eine Richtung selbst ein Blatt auslösen kann (`sheet(item:)`).
nonisolated extension Direction: Identifiable {
    var id: String { rawValue }
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

    init(
        id: UUID = UUID(),
        date: CalendarDate = .today(),
        amount: Decimal,
        direction: Direction,
        categoryID: UUID,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.amount = max(0, amount)
        self.direction = direction
        self.categoryID = categoryID
        self.note = note
        self.createdAt = createdAt
    }

    var month: YearMonth { date.yearMonth }

    /// Vorzeichenbehaftet, für die Netto-Rechnung in der Ringmitte.
    var signedAmount: Decimal { direction == .income ? amount : -amount }
}
