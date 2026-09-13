import Foundation
import Testing
@testable import money_

struct BudgetCalculatorTests {
    let groceries = BudgetCategory(name: "Lebensmittel", kind: .spending, sortIndex: 0)
    let restaurants = BudgetCategory(name: "Restaurants", kind: .spending, sortIndex: 1)
    let rent = BudgetCategory(name: "Miete", kind: .fixed, sortIndex: 2)
    let salary = BudgetCategory(name: "Gehalt", kind: .income, sortIndex: 3)

    let august = YearMonth(year: 2026, month: 8)
    let july = YearMonth(year: 2026, month: 7)

    private var categories: [BudgetCategory] { [groceries, restaurants, rent, salary] }

    private var rules: [Rule] {
        [
            Rule(categoryID: groceries.id, matcher: .mcc("5411")),
            Rule(categoryID: restaurants.id, matcher: .mcc("5812")),
            Rule(categoryID: rent.id, matcher: .pattern(Pattern("Miete"))),
            Rule(categoryID: salary.id, matcher: .pattern(Pattern("Gehalt"))),
        ]
    }

    private func overview(
        _ transactions: [Transaction],
        budgets: [BudgetCategory.ID: Decimal],
        month: YearMonth? = nil,
        sort: BudgetSort = .urgency
    ) -> MonthlyOverview {
        BudgetCalculator.overview(
            month: month ?? august,
            transactions: transactions,
            categories: categories,
            budgets: budgets,
            categorizer: Categorizer(rules: rules),
            sort: sort)
    }

    // MARK: Remaining

    @Test func remainingIsBudgetMinusSpend() throws {
        let result = overview(
            [
                Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-36.75", id: "a"),
                Fixtures.card(merchant: "ALDI", mcc: "5411", amount: "-27.81", id: "b"),
            ],
            budgets: [groceries.id: 400])

        let row = try #require(result.spending.first { $0.id == groceries.id })
        #expect(row.spent == Decimal(string: "64.56")!)
        #expect(row.remaining == Decimal(string: "335.44")!)
        #expect(row.transactionCount == 2)
        #expect(row.isOverspent == false)
    }

    @Test func aRefundGivesBudgetBack() throws {
        let result = overview(
            [
                Fixtures.card(merchant: "Alte Utting", mcc: "5812", amount: "-50", id: "a"),
                Fixtures.card(merchant: "Alte Utting", mcc: "5812", amount: "2", id: "b"),
            ],
            budgets: [restaurants.id: 200])

        let row = try #require(result.spending.first { $0.id == restaurants.id })
        #expect(row.spent == 48)
        #expect(row.remaining == 152)
    }

    @Test func overspendingGoesNegativeRatherThanClamping() throws {
        let result = overview(
            [Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-450", id: "a")],
            budgets: [groceries.id: 400])

        let row = try #require(result.spending.first { $0.id == groceries.id })
        #expect(row.remaining == -50)
        #expect(row.isOverspent)
        #expect(row.fraction == 1)
    }

    @Test func aCategoryWithoutABudgetShowsItsSpendAnyway() throws {
        let result = overview(
            [Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-20", id: "a")],
            budgets: [:])

        let row = try #require(result.spending.first { $0.id == groceries.id })
        #expect(row.budget == 0)
        #expect(row.remaining == -20)
    }

    @Test func theFeeIsPartOfTheSpend() throws {
        var atm = Fixtures.card(merchant: "UBUDPASAR", mcc: "5411", amount: "-53.06", id: "a")
        atm = Transaction(
            id: atm.id, timestamp: atm.timestamp, bookingDate: atm.bookingDate,
            account: atm.account, type: atm.type, merchant: atm.merchant, detail: atm.detail,
            amount: atm.amount, fee: -1, tax: 0, currency: atm.currency,
            originalAmount: nil, originalCurrency: nil, fxRate: nil, counterpartyName: nil,
            counterpartyIBAN: nil, paymentReference: nil, mcc: atm.mcc)

        let result = overview([atm], budgets: [groceries.id: 100])
        let row = try #require(result.spending.first { $0.id == groceries.id })
        #expect(row.spent == Decimal(string: "54.06")!)
    }

    // MARK: Month boundaries

    @Test func onlyTheSelectedMonthCounts() throws {
        let result = overview(
            [
                Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-10",
                              date: CalendarDate(year: 2026, month: 8, day: 1), id: "a"),
                Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-999",
                              date: CalendarDate(year: 2026, month: 7, day: 31), id: "b"),
            ],
            budgets: [groceries.id: 400])

        #expect(try #require(result.spending.first { $0.id == groceries.id }).spent == 10)

        let previous = overview(
            [
                Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-10",
                              date: CalendarDate(year: 2026, month: 8, day: 1), id: "a"),
                Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-999",
                              date: CalendarDate(year: 2026, month: 7, day: 31), id: "b"),
            ],
            budgets: [groceries.id: 400], month: july)
        #expect(try #require(previous.spending.first { $0.id == groceries.id }).spent == 999)
    }

    @Test func recomputingFromScratchGivesTheSameAnswer() throws {
        let transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        let budgets: [BudgetCategory.ID: Decimal] = [groceries.id: 400, restaurants.id: 200]
        let first = overview(transactions, budgets: budgets)
        let second = overview(transactions.reversed(), budgets: budgets)
        // Order of the input must not change a single number.
        #expect(first == second)
    }

    // MARK: Sections

    @Test func aFixedCostReportsWhetherItHasBeenDebited() throws {
        let unpaid = overview([], budgets: [rent.id: 1200])
        let unpaidRow = try #require(unpaid.fixedCosts.first)
        #expect(unpaidRow.isSettled == false)
        #expect(unpaidRow.outstanding == 1200)

        let paid = overview(
            [Fixtures.card(merchant: "Miete August", mcc: nil, amount: "-1200", id: "a")],
            budgets: [rent.id: 1200])
        let paidRow = try #require(paid.fixedCosts.first)
        #expect(paidRow.isSettled)
        #expect(paidRow.outstanding == 0)
        #expect(paidRow.booked == 1200)
    }

    @Test func aPartlyDebitedFixedCostIsNotSettled() throws {
        let result = overview(
            [Fixtures.card(merchant: "Miete Anzahlung", mcc: nil, amount: "-600", id: "a")],
            budgets: [rent.id: 1200])
        let row = try #require(result.fixedCosts.first)
        #expect(row.isSettled == false)
        #expect(row.outstanding == 600)
    }

    @Test func incomeIsReportedAsAPositiveNumber() throws {
        let result = overview(
            [Fixtures.card(merchant: "Gehalt August", mcc: nil, amount: "2400", id: "a")],
            budgets: [:])
        let row = try #require(result.income.first)
        #expect(row.received == 2400)
        #expect(result.totalIncome == 2400)
    }

    @Test func incomeNeverTouchesTheRemainingBudget() throws {
        let result = overview(
            [
                Fixtures.card(merchant: "Gehalt August", mcc: nil, amount: "2400", id: "a"),
                Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-100", id: "b"),
            ],
            budgets: [groceries.id: 400])
        #expect(result.totalRemaining == 300)
    }

    // MARK: Ordering and the Inbox

    @Test func urgencyPutsTheTightestBudgetFirst() throws {
        let result = overview(
            [
                Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-390", id: "a"),
                Fixtures.card(merchant: "Alte Utting", mcc: "5812", amount: "-10", id: "b"),
            ],
            budgets: [groceries.id: 400, restaurants.id: 200])
        #expect(result.spending.map(\.category.name) == ["Lebensmittel", "Restaurants"])
    }

    @Test func manualOrderIgnoresUrgency() throws {
        let result = overview(
            [Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-390", id: "a")],
            budgets: [groceries.id: 400, restaurants.id: 200], sort: .manual)
        #expect(result.spending.map(\.category.sortIndex) == [0, 1])
    }

    @Test func theInboxCountSpansEveryMonth() throws {
        let result = overview(
            [
                Fixtures.card(merchant: "Unbekannt", mcc: nil, amount: "-5",
                              date: CalendarDate(year: 2026, month: 8, day: 2), id: "a"),
                Fixtures.card(merchant: "Auch unbekannt", mcc: nil, amount: "-5",
                              date: CalendarDate(year: 2026, month: 3, day: 2), id: "b"),
                Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-5", id: "c"),
            ],
            budgets: [:])
        // An old unassigned booking is still work to do.
        #expect(result.inboxCount == 2)
    }

    @Test func securitiesRowsAreInvisibleToTheBudget() throws {
        let transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        let result = BudgetCalculator.overview(
            month: august, transactions: transactions, categories: categories,
            budgets: [groceries.id: 400],
            categorizer: Categorizer(rules: rules + [
                // Would catch the trading rows if they ever reached the calculator.
                Rule(categoryID: groceries.id, matcher: .pattern(Pattern("Sell trade"))),
            ]))
        let row = try #require(result.spending.first { $0.id == groceries.id })
        #expect(row.spent == Decimal(string: "36.75")!)
    }

    // MARK: Drill-down

    @Test func theDetailListIsNewestFirstAndScopedToTheMonth() throws {
        let transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        let result = BudgetCalculator.transactions(
            in: groceries.id, month: august, transactions: transactions,
            categorizer: Categorizer(rules: rules))
        #expect(result.map(\.merchant) == ["EDEKA Muenchen. Impler"])

        let cashInAugust2025 = BudgetCalculator.transactions(
            in: groceries.id, month: YearMonth(year: 2025, month: 8), transactions: transactions,
            categorizer: Categorizer(rules: rules))
        #expect(cashInAugust2025.isEmpty)
    }
}
