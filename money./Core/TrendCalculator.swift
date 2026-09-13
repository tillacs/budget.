import Foundation

/// "139 € — im Schnitt der letzten drei Monate waren es 190 €". A bare number cannot answer
/// "is that a lot"; this can.
nonisolated struct CategoryComparison: Equatable, Sendable {
    let current: Decimal
    let average: Decimal
    /// How many earlier months actually had data. Averaging over months the export does not
    /// cover would drag the figure toward zero and quietly flatter the user.
    let monthsCompared: Int

    var delta: Decimal { current - average }
    var isAbove: Bool { delta > 0 }
}

nonisolated enum TrendCalculator {
    static func comparison(
        for categoryID: BudgetCategory.ID,
        month: YearMonth,
        transactions: [Transaction],
        categorizer: Categorizer,
        lookback: Int = 3
    ) -> CategoryComparison? {
        guard lookback > 0 else { return nil }
        let assignments = categorizer.assignments(for: transactions)

        var spendByMonth: [YearMonth: Decimal] = [:]
        var monthsWithAnyData: Set<YearMonth> = []

        for transaction in transactions where transaction.isCash {
            monthsWithAnyData.insert(transaction.month)
            guard assignments[transaction.id]?.categoryID == categoryID else { continue }
            spendByMonth[transaction.month, default: 0] += transaction.spend
        }

        let earlier = (1...lookback)
            .map { month.advanced(by: -$0) }
            // A month the export does not reach is not a month with zero spending.
            .filter { monthsWithAnyData.contains($0) }
        guard !earlier.isEmpty else { return nil }

        let total = earlier.reduce(Decimal(0)) { $0 + (spendByMonth[$1] ?? 0) }
        return CategoryComparison(
            current: spendByMonth[month] ?? 0,
            average: total / Decimal(earlier.count),
            monthsCompared: earlier.count)
    }
}
