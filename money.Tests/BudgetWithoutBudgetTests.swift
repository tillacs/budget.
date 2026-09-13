import Foundation
import Testing
@testable import money_

/// A fresh import has categories but no budgets yet. That state has to read as "unanswered",
/// not as "you blew every budget".
struct UnbudgetedCategoryTests {
    let groceries = BudgetCategory(name: "Lebensmittel", kind: .spending, sortIndex: 0)
    let restaurants = BudgetCategory(name: "Restaurants", kind: .spending, sortIndex: 1)

    private var rules: [Rule] {
        [
            Rule(categoryID: groceries.id, matcher: .mcc("5411")),
            Rule(categoryID: restaurants.id, matcher: .mcc("5812")),
        ]
    }

    private func overview(
        budgets: [BudgetCategory.ID: Decimal],
        sort: BudgetSort = .urgency
    ) -> MonthlyOverview {
        BudgetCalculator.overview(
            month: YearMonth(year: 2026, month: 8),
            transactions: [
                Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-120", id: "a"),
                Fixtures.card(merchant: "Alte Utting", mcc: "5812", amount: "-40", id: "b"),
            ],
            categories: [groceries, restaurants],
            budgets: budgets,
            categorizer: Categorizer(rules: rules),
            sort: sort)
    }

    @Test func withoutAnyBudgetTheHeadlineIsNotNegative() throws {
        let result = overview(budgets: [:])
        #expect(result.totalBudget == 0)
        #expect(result.totalRemaining == 0)
        #expect(result.untrackedSpend == 160)
        #expect(result.spending.allSatisfy { !$0.isOverspent })
    }

    @Test func spendInAnUnbudgetedCategoryStaysOutOfTheHeadline() throws {
        let result = overview(budgets: [groceries.id: 400])
        #expect(result.totalBudget == 400)
        #expect(result.totalSpent == 120)
        #expect(result.totalRemaining == 280)
        // The 40 € of restaurants is reported, just not mixed into the one number.
        #expect(result.untrackedSpend == 40)
    }

    @Test func anUnbudgetedCategoryIsNotOverspent() throws {
        let result = overview(budgets: [:])
        let row = try #require(result.spending.first { $0.id == groceries.id })
        #expect(row.hasBudget == false)
        #expect(row.isOverspent == false)
        #expect(row.spent == 120)
    }

    @Test func urgencySortsBudgetedCategoriesAboveUnbudgetedOnes() throws {
        // Restaurants has the more negative "remaining" but no budget, so it must not lead.
        let result = overview(budgets: [groceries.id: 130])
        #expect(result.spending.map(\.category.name) == ["Lebensmittel", "Restaurants"])
        #expect(result.spending.first?.hasBudget == true)
    }

    @Test func settingABudgetPutsTheCategoryBackInTheHeadline() throws {
        let before = overview(budgets: [:])
        let after = overview(budgets: [groceries.id: 400, restaurants.id: 200])
        #expect(before.totalRemaining == 0)
        #expect(after.totalRemaining == 440)
        #expect(after.untrackedSpend == 0)
    }
}
