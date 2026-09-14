// MonthSummary.swift
// budget. — die ganze Rechnung der App
//
// Es gibt genau eine Seite, also genau eine Auswertung: ein Monat, zwei Ringe.
// Der größere Ring füllt den Kreis ganz, der kleinere bekommt denselben Maßstab.
// Dadurch ist die Lücke im kürzeren Ring das, was am Monatsende übrig bleibt —
// die Grafik muss das nicht beschriften, sie zeigt es.

import Foundation

/// Ein Segment eines Rings: eine Kategorie mit ihrer Monatssumme.
nonisolated struct Slice: Identifiable, Hashable, Sendable {
    let category: BudgetCategory
    let total: Decimal
    let count: Int
    /// Anteil am eigenen Ring (0…1). Die Anteile eines Rings summieren sich auf 1.
    let share: Double

    var id: UUID { category.id }
}

/// Ein Ring: eine Richtung, ihre Summe, ihre Segmente.
nonisolated struct RingSummary: Hashable, Sendable {
    let direction: Direction
    let total: Decimal
    let slices: [Slice]

    var isEmpty: Bool { slices.isEmpty }
}

nonisolated struct MonthSummary: Hashable, Sendable {
    let month: YearMonth
    let expenses: RingSummary
    let income: RingSummary

    /// Was übrig bleibt. Negativ heißt: mehr ausgegeben als eingenommen.
    var net: Decimal { income.total - expenses.total }

    var isEmpty: Bool { expenses.isEmpty && income.isEmpty }

    /// Der gemeinsame Maßstab beider Ringe.
    var scale: Decimal { max(expenses.total, income.total) }

    func ring(_ direction: Direction) -> RingSummary {
        direction == .expense ? expenses : income
    }

    /// Wie viel vom Vollkreis dieser Ring einnimmt (0…1). Der größere Ring bekommt
    /// immer die 1 — sonst hätte man zwei Kreise ohne gemeinsamen Bezug.
    func sweep(_ direction: Direction) -> Double {
        let scale = scale
        guard scale > 0 else { return 0 }
        return min(1, max(0, (ring(direction).total / scale).doubleValue))
    }

    static func make(
        month: YearMonth,
        entries: [Entry],
        categories: [BudgetCategory]
    ) -> MonthSummary {
        let inMonth = entries.filter { $0.month == month }
        return MonthSummary(
            month: month,
            expenses: ring(.expense, from: inMonth, categories: categories),
            income: ring(.income, from: inMonth, categories: categories))
    }

    private static func ring(
        _ direction: Direction,
        from entries: [Entry],
        categories: [BudgetCategory]
    ) -> RingSummary {
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var totals: [UUID: (sum: Decimal, count: Int)] = [:]

        for entry in entries where entry.direction == direction {
            // Eine Buchung, deren Kategorie gelöscht wurde, fällt hier raus. Sie bleibt
            // aber in der Datei — das Löschen einer Kategorie bietet deshalb an, ihre
            // Buchungen mitzunehmen.
            guard byID[entry.categoryID] != nil else { continue }
            let current = totals[entry.categoryID] ?? (0, 0)
            totals[entry.categoryID] = (current.sum + entry.amount, current.count + 1)
        }

        let total = totals.values.reduce(Decimal(0)) { $0 + $1.sum }
        let slices = totals.compactMap { id, value -> Slice? in
            guard let category = byID[id], value.sum > 0 else { return nil }
            return Slice(
                category: category,
                total: value.sum,
                count: value.count,
                share: total > 0 ? (value.sum / total).doubleValue : 0)
        }
        // Größtes Segment zuerst: Der Ring beginnt oben mit dem, was am meisten wiegt,
        // und die Liste darunter hat dieselbe Reihenfolge wie die Grafik.
        .sorted {
            $0.total == $1.total ? $0.category.name < $1.category.name : $0.total > $1.total
        }

        return RingSummary(direction: direction, total: total, slices: slices)
    }
}

nonisolated extension Array where Element == Entry {
    /// Buchungen einer Kategorie in einem Monat, neueste zuerst.
    func of(category id: UUID, in month: YearMonth) -> [Entry] {
        filter { $0.categoryID == id && $0.month == month }
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }

    /// Alle Monate, in denen etwas erfasst wurde — für die Monatsnavigation, damit
    /// man nicht endlos in leere Monate zurückblättert.
    var recordedMonths: Set<YearMonth> { Set(map(\.month)) }
}

nonisolated extension Decimal {
    /// Nur für die Geometrie. Beträge selbst bleiben `Decimal`.
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
