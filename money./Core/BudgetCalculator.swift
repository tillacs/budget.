import Foundation

nonisolated enum BudgetSort: String, Hashable, Codable, Sendable, CaseIterable {
    /// Least remaining first — the category about to run out is the one worth seeing.
    case urgency
    /// The order the user arranged.
    case manual
}

nonisolated struct SpendingProgress: Identifiable, Equatable, Sendable {
    let category: BudgetCategory
    let budget: Decimal
    let spent: Decimal
    let transactionCount: Int

    var id: BudgetCategory.ID { category.id }
    var remaining: Decimal { budget - spent }
    /// A category with no budget yet is not overspent — it is unanswered. Without this, a
    /// fresh import would paint every row red before the user has set a single number.
    var hasBudget: Bool { budget > 0 }
    var isOverspent: Bool { hasBudget && remaining < 0 }

    /// Fill level, clamped to 0…1. Display only, never money.
    ///
    /// Without a budget there is no limit to be close to, so the answer is zero rather than
    /// full — a category nobody has set up must not look maxed out.
    var fraction: Double {
        guard budget > 0 else { return 0 }
        return min(max((spent / budget).doubleValue, 0), 1)
    }
}

nonisolated struct FixedCostProgress: Identifiable, Equatable, Sendable {
    let category: BudgetCategory
    let expected: Decimal
    let booked: Decimal
    let transactionCount: Int

    var id: BudgetCategory.ID { category.id }
    /// A fixed cost asks "has it gone out yet?", not "how much is left?".
    var isSettled: Bool { transactionCount > 0 && booked >= expected }
    var outstanding: Decimal { max(0, expected - booked) }
}

nonisolated struct IncomeTotal: Identifiable, Equatable, Sendable {
    let category: BudgetCategory
    let received: Decimal
    let transactionCount: Int

    var id: BudgetCategory.ID { category.id }
}

/// Every euro that moved this month, whether or not it found a category.
///
/// This exists so that nothing can go missing: the totals are computed straight from the
/// bookings, never by adding up categories. An uncategorized purchase is invisible to the
/// budgets but not to this.
nonisolated struct MonthlyFlow: Equatable, Sendable {
    let inflow: Decimal
    let outflow: Decimal
    let cardOutflow: Decimal
    let transferOutflow: Decimal
    let otherOutflow: Decimal
    /// Spending that reached no category at all.
    let uncategorizedOutflow: Decimal
    let uncategorizedCount: Int

    var net: Decimal { inflow - outflow }

    static let zero = MonthlyFlow(
        inflow: 0, outflow: 0, cardOutflow: 0, transferOutflow: 0, otherOutflow: 0,
        uncategorizedOutflow: 0, uncategorizedCount: 0)
}

nonisolated struct MonthlyOverview: Equatable, Sendable {
    let month: YearMonth
    let spending: [SpendingProgress]
    let fixedCosts: [FixedCostProgress]
    let income: [IncomeTotal]
    /// Unassigned cash bookings across all months — the Inbox badge.
    let inboxCount: Int
    let flow: MonthlyFlow

    /// The headline only covers categories that actually have a budget. Spend in a category
    /// the user has not budgeted yet is reported separately rather than dragging the one
    /// number on the screen into the red.
    var totalBudget: Decimal { spending.filter(\.hasBudget).reduce(0) { $0 + $1.budget } }
    var totalSpent: Decimal { spending.filter(\.hasBudget).reduce(0) { $0 + $1.spent } }
    var totalRemaining: Decimal { totalBudget - totalSpent }
    var untrackedSpend: Decimal { spending.filter { !$0.hasBudget }.reduce(0) { $0 + $1.spent } }
    var totalIncome: Decimal { income.reduce(0) { $0 + $1.received } }
    var outstandingFixedCosts: Decimal { fixedCosts.reduce(0) { $0 + $1.outstanding } }

    static let empty = MonthlyOverview(
        month: YearMonth(year: 2026, month: 1), spending: [], fixedCosts: [], income: [],
        inboxCount: 0, flow: .zero)
}

/// Everything here is recomputed from the transactions on every call. No counter is stored,
/// so nothing can drift away from the CSV.
nonisolated enum BudgetCalculator {
    static func overview(
        month: YearMonth,
        transactions: [Transaction],
        categories: [BudgetCategory],
        budgets: [BudgetCategory.ID: Decimal],
        categorizer: Categorizer,
        sort: BudgetSort = .urgency
    ) -> MonthlyOverview {
        let assignments = categorizer.assignments(for: transactions)

        var spendByCategory: [BudgetCategory.ID: Decimal] = [:]
        var countByCategory: [BudgetCategory.ID: Int] = [:]
        var inboxCount = 0

        var inflow: Decimal = 0
        var outflow: Decimal = 0
        var cardOutflow: Decimal = 0
        var transferOutflow: Decimal = 0
        var otherOutflow: Decimal = 0
        var uncategorizedOutflow: Decimal = 0
        var uncategorizedCount = 0

        for transaction in transactions where transaction.isCash {
            guard let assignment = assignments[transaction.id] else { continue }
            if assignment.needsReview { inboxCount += 1 }
            guard transaction.month == month else { continue }

            // Totals come from the bookings themselves, never from the category rows, so a
            // purchase nobody has classified still shows up in what was spent.
            let spend = transaction.spend
            if spend > 0 {
                outflow += spend
                if transaction.isCardPayment {
                    cardOutflow += spend
                } else if transaction.isTransfer {
                    transferOutflow += spend
                } else {
                    otherOutflow += spend
                }
                if assignment.categoryID == nil {
                    uncategorizedOutflow += spend
                    uncategorizedCount += 1
                }
            } else {
                inflow += -spend
            }

            guard let categoryID = assignment.categoryID else { continue }
            spendByCategory[categoryID, default: 0] += spend
            countByCategory[categoryID, default: 0] += 1
        }

        let flow = MonthlyFlow(
            inflow: inflow, outflow: outflow, cardOutflow: cardOutflow,
            transferOutflow: transferOutflow, otherOutflow: otherOutflow,
            uncategorizedOutflow: uncategorizedOutflow, uncategorizedCount: uncategorizedCount)

        var spending: [SpendingProgress] = []
        var fixedCosts: [FixedCostProgress] = []
        var income: [IncomeTotal] = []

        for category in categories {
            let spent = spendByCategory[category.id] ?? 0
            let count = countByCategory[category.id] ?? 0
            switch category.kind {
            case .spending:
                spending.append(SpendingProgress(
                    category: category, budget: budgets[category.id] ?? 0,
                    spent: spent, transactionCount: count))
            case .fixed:
                fixedCosts.append(FixedCostProgress(
                    category: category, expected: budgets[category.id] ?? 0,
                    booked: spent, transactionCount: count))
            case .income:
                // Inflows are negative spend; report them the way a person reads them.
                income.append(IncomeTotal(
                    category: category, received: -spent, transactionCount: count))
            }
        }

        switch sort {
        case .urgency:
            // Budgeted categories first, tightest on top. Unbudgeted ones have no urgency
            // to report, so they sit below by size of spend rather than swamping the list
            // with their negative "remaining".
            spending.sort { left, right in
                if left.hasBudget != right.hasBudget { return left.hasBudget }
                if left.hasBudget {
                    if left.remaining != right.remaining { return left.remaining < right.remaining }
                } else if left.spent != right.spent {
                    return left.spent > right.spent
                }
                return left.category.name.localizedCaseInsensitiveCompare(right.category.name)
                    == .orderedAscending
            }
        case .manual:
            spending.sort { $0.category.sortIndex < $1.category.sortIndex }
        }
        fixedCosts.sort { $0.category.sortIndex < $1.category.sortIndex }
        income.sort { $0.category.sortIndex < $1.category.sortIndex }

        return MonthlyOverview(
            month: month, spending: spending, fixedCosts: fixedCosts, income: income,
            inboxCount: inboxCount, flow: flow)
    }

    /// The bookings behind one row, newest first.
    static func transactions(
        in category: BudgetCategory.ID,
        month: YearMonth,
        transactions: [Transaction],
        categorizer: Categorizer
    ) -> [Transaction] {
        let assignments = categorizer.assignments(for: transactions)
        return transactions
            .filter {
                $0.isCash && $0.month == month && assignments[$0.id]?.categoryID == category
            }
            .sorted {
                $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp > $1.timestamp
            }
    }
}

nonisolated extension Decimal {
    /// Only for ratios and layout. Money never takes this path.
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
