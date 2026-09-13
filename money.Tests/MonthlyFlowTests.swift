import Foundation
import Testing
@testable import money_

/// The promise that nothing gets lost: the month totals are computed from the bookings, not
/// by adding up categories, so an unclassified purchase still shows in what was spent.
struct MonthlyFlowTests {
    let groceries = BudgetCategory(name: "Lebensmittel", kind: .spending, sortIndex: 0)
    let salary = BudgetCategory(name: "Gehalt", kind: .income, sortIndex: 1)
    let august = YearMonth(year: 2026, month: 8)

    private var rules: [Rule] {
        [
            Rule(categoryID: groceries.id, matcher: .mcc("5411")),
            Rule(categoryID: salary.id, matcher: .pattern(Pattern("Gehalt"))),
        ]
    }

    private func overview(
        _ transactions: [Transaction],
        budgets: [BudgetCategory.ID: Decimal] = [:]
    ) -> MonthlyOverview {
        BudgetCalculator.overview(
            month: august,
            transactions: transactions,
            categories: [groceries, salary],
            budgets: budgets,
            categorizer: Categorizer(rules: rules))
    }

    private func transfer(_ merchant: String, _ amount: String, id: String) -> Transaction {
        Transaction(
            id: id, timestamp: Date(timeIntervalSince1970: 1_775_000_000),
            bookingDate: CalendarDate(year: 2026, month: 8, day: 4), account: .cash,
            type: TransactionType(rawValue: "TRANSFER_DIRECT_DEBIT_INBOUND"),
            merchant: merchant, detail: merchant,
            amount: TransactionCSVParser.decimal(from: amount)!, fee: 0, tax: 0, currency: "EUR",
            originalAmount: nil, originalCurrency: nil, fxRate: nil, counterpartyName: nil,
            counterpartyIBAN: nil, paymentReference: nil, mcc: nil)
    }

    // MARK: Nothing gets lost

    @Test func unclassifiedSpendStillCountsInTheTotal() throws {
        let result = overview([
            Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-40", id: "a"),
            Fixtures.card(merchant: "Völlig unbekannt", mcc: nil, amount: "-25", id: "b"),
        ])

        #expect(result.flow.outflow == 65)
        #expect(result.flow.uncategorizedOutflow == 25)
        #expect(result.flow.uncategorizedCount == 1)
        // The budget only knows about the 40 — the total knows about both.
        #expect(result.spending.first { $0.id == groceries.id }?.spent == 40)
    }

    @Test func theTotalMatchesTheSumOfEveryCashBooking() throws {
        let transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        let result = BudgetCalculator.overview(
            month: YearMonth(year: 2026, month: 8), transactions: transactions,
            categories: [], budgets: [:], categorizer: Categorizer(rules: []))

        let expected = transactions
            .filter { $0.isCash && $0.month == YearMonth(year: 2026, month: 8) }
            .reduce(Decimal(0)) { $0 + max(0, $1.spend) }
        #expect(result.flow.outflow == expected)
        // With no categories at all, every last cent is reported as uncategorized.
        #expect(result.flow.uncategorizedOutflow == expected)
    }

    // MARK: Card versus transfer

    @Test func spendingIsSplitByHowTheMoneyLeft() throws {
        let result = overview([
            Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-40", id: "a"),
            Fixtures.card(merchant: "Alte Utting", mcc: "5812", amount: "-10", id: "b"),
            transfer("Miete August", "-1250", id: "c"),
        ])

        #expect(result.flow.outflow == 1300)
        #expect(result.flow.cardOutflow == 50)
        #expect(result.flow.transferOutflow == 1250)
        #expect(result.flow.otherOutflow == 0)
    }

    @Test func feesAndInterestLandInSonstiges() throws {
        let fee = Transaction(
            id: "fee", timestamp: Date(timeIntervalSince1970: 1_775_000_000),
            bookingDate: CalendarDate(year: 2026, month: 8, day: 4), account: .cash,
            type: TransactionType(rawValue: "ACCOUNT_FEE"), merchant: "", detail: "Gebühr",
            amount: TransactionCSVParser.decimal(from: "-3.50")!, fee: 0, tax: 0,
            currency: "EUR", originalAmount: nil, originalCurrency: nil, fxRate: nil,
            counterpartyName: nil, counterpartyIBAN: nil, paymentReference: nil, mcc: nil)

        let result = overview([fee])
        #expect(result.flow.otherOutflow == Decimal(string: "3.50")!)
        #expect(result.flow.cardOutflow == 0)
        #expect(result.flow.transferOutflow == 0)
    }

    @Test func theThreeSplitsAlwaysAddUpToTheTotal() throws {
        let transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        for month in [YearMonth(year: 2026, month: 8), YearMonth(year: 2025, month: 8),
                      YearMonth(year: 2024, month: 5)] {
            let flow = BudgetCalculator.overview(
                month: month, transactions: transactions, categories: [], budgets: [:],
                categorizer: Categorizer(rules: [])).flow
            #expect(flow.cardOutflow + flow.transferOutflow + flow.otherOutflow == flow.outflow)
        }
    }

    // MARK: In and out

    @Test func inflowAndOutflowAreReportedSeparately() throws {
        let result = overview([
            Fixtures.card(merchant: "Gehalt August", mcc: nil, amount: "2480", id: "a"),
            Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-40", id: "b"),
        ])

        #expect(result.flow.inflow == 2480)
        #expect(result.flow.outflow == 40)
        #expect(result.flow.net == 2440)
    }

    @Test func aRefundReducesSpendRatherThanCountingAsIncome() throws {
        let result = overview([
            Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-40", id: "a"),
            Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "5", id: "b"),
        ])
        // The refund is an inflow by sign, and that is exactly how a person reads it.
        #expect(result.flow.outflow == 40)
        #expect(result.flow.inflow == 5)
        #expect(result.flow.net == -35)
        #expect(result.spending.first { $0.id == groceries.id }?.spent == 35)
    }

    @Test func securitiesBookingsAreInvisibleToTheTotals() throws {
        let transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        let result = BudgetCalculator.overview(
            month: YearMonth(year: 2026, month: 8), transactions: transactions,
            categories: [], budgets: [:], categorizer: Categorizer(rules: []))

        let tradingSpend = transactions
            .filter { !$0.isCash && $0.month == YearMonth(year: 2026, month: 8) }
            .reduce(Decimal(0)) { $0 + max(0, $1.spend) }
        #expect(tradingSpend > 0)
        #expect(result.flow.outflow < tradingSpend + result.flow.outflow)
    }

    @Test func anEmptyMonthReportsZeroRatherThanNothing() throws {
        let result = overview([])
        #expect(result.flow == MonthlyFlow.zero)
        #expect(result.flow.net == 0)
    }
}
