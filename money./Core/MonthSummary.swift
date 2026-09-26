// MonthSummary.swift
// budget. — die ganze Rechnung der App
//
// Ein Monat, drei Ringe: Ausgaben, Einnahmen, Investiert. Der größte füllt den Kreis
// ganz, die anderen bekommen denselben Maßstab. Vorschläge zählen nicht mit — sie
// stehen daneben, gestrichelt. Umbuchungen zählen nie. Erstattungen senken die
// Kategorie, aus der das Geld zurückkommt.

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
    let invested: RingSummary
    /// Was noch im Posteingang wartet, je Richtung nach vorgeschlagener Kategorie.
    let pending: [Direction: [Slice]]
    let transferTotal: Decimal
    let transferCount: Int
    /// Neutral: Umbuchungen und Ausgleiche. Geld, das sich bewegt hat, ohne etwas
    /// zu kosten oder zu bringen. Zählt nirgends, steht aber nicht im Verborgenen.
    let neutralTotal: Decimal
    let neutralCount: Int

    /// Was übrig bleibt, nachdem auch das Depot bedient ist. Negativ heißt: mehr
    /// ausgegeben und angelegt als eingenommen.
    var net: Decimal { income.total - expenses.total - invested.total }

    var isEmpty: Bool { expenses.isEmpty && income.isEmpty && invested.isEmpty }
    var hasPending: Bool { pending.values.contains { !$0.isEmpty } }
    var pendingCount: Int { pending.values.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } } }

    /// Der gemeinsame Maßstab aller Ringe.
    var scale: Decimal { max(expenses.total, income.total, invested.total) }

    func ring(_ direction: Direction) -> RingSummary {
        switch direction {
        case .expense: return expenses
        case .income: return income
        case .invest: return invested
        }
    }

    /// Wie viel vom Vollkreis dieser Ring einnimmt (0…1). Der größte Ring bekommt
    /// immer die 1 — sonst hätte man Kreise ohne gemeinsamen Bezug.
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
        let counting = inMonth.filter(\.counts)
        let proposed = inMonth.filter { $0.status == .proposed && $0.kind != .transfer }
        let transfers = inMonth.filter { $0.kind == .transfer }
        let refunds = inMonth.filter { $0.kind == .refund && $0.status != .proposed }
        var pending: [Direction: [Slice]] = [:]
        for direction in Direction.allCases {
            let slices = ring(direction, from: proposed, categories: categories).slices
            if !slices.isEmpty { pending[direction] = slices }
        }
        return MonthSummary(
            month: month,
            expenses: ring(.expense, from: counting, categories: categories),
            income: ring(.income, from: counting, categories: categories),
            invested: ring(.invest, from: counting, categories: categories),
            pending: pending,
            transferTotal: transfers.reduce(0) { $0 + $1.amount },
            transferCount: transfers.count,
            neutralTotal: (transfers + refunds).reduce(0) { $0 + $1.amount },
            neutralCount: transfers.count + refunds.count)
    }

    private static func ring(
        _ direction: Direction,
        from entries: [Entry],
        categories: [BudgetCategory]
    ) -> RingSummary {
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var totals: [UUID: (sum: Decimal, count: Int)] = [:]

        for entry in entries where entry.direction == direction {
            // Eine Buchung, deren Kategorie gelöscht wurde, fällt hier raus.
            guard byID[entry.categoryID] != nil else { continue }
            let current = totals[entry.categoryID] ?? (0, 0)
            if entry.kind == .refund {
                totals[entry.categoryID] = (current.sum - entry.amount, current.count)
            } else {
                totals[entry.categoryID] = (current.sum + entry.amount, current.count + 1)
            }
        }

        // Eine Kategorie, in der mehr zurückkam als ausgegeben wurde, steht bei null —
        // ein negatives Segment gibt es nicht.
        let positive = totals.mapValues { (sum: max(0, $0.sum), count: $0.count) }
        let total = positive.values.reduce(Decimal(0)) { $0 + $1.sum }
        let slices = positive.compactMap { id, value -> Slice? in
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
    /// Buchungen einer Kategorie in einem Monat, neueste zuerst. Vorschläge bleiben
    /// draußen — die stehen im Posteingang.
    func of(category id: UUID, in month: YearMonth) -> [Entry] {
        filter { $0.categoryID == id && $0.month == month && $0.status != .proposed }
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
