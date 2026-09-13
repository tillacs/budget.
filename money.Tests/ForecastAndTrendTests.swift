import Foundation
import Testing
@testable import money_

struct ForecastTests {
    let groceries = BudgetCategory(name: "Lebensmittel", kind: .spending, sortIndex: 0)
    let rent = BudgetCategory(name: "Miete", kind: .fixed, sortIndex: 1)
    let august = YearMonth(year: 2026, month: 8)

    private func overview(
        spent: String,
        budget: Decimal = 400,
        rentExpected: Decimal = 0,
        rentBooked: String? = nil
    ) -> MonthlyOverview {
        var transactions = [
            Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-\(spent)",
                          date: CalendarDate(year: 2026, month: 8, day: 2), id: "a"),
        ]
        if let rentBooked {
            transactions.append(Fixtures.card(
                merchant: "Miete August", mcc: nil, amount: "-\(rentBooked)",
                date: CalendarDate(year: 2026, month: 8, day: 1), id: "r"))
        }
        return BudgetCalculator.overview(
            month: august,
            transactions: transactions,
            categories: [groceries, rent],
            budgets: [groceries.id: budget, rent.id: rentExpected],
            categorizer: Categorizer(rules: [
                Rule(categoryID: groceries.id, matcher: .mcc("5411")),
                Rule(categoryID: rent.id, matcher: .pattern(Pattern("Miete"))),
            ]))
    }

    @Test func halfwayThroughTheMonthTheRunRateDoubles() throws {
        let forecast = try #require(ForecastCalculator.forecast(
            for: overview(spent: "100"),
            today: CalendarDate(year: 2026, month: 8, day: 15)))

        #expect(forecast.daysInMonth == 31)
        #expect(forecast.spentSoFar == 100)
        // 100 € in 15 of 31 days.
        #expect(forecast.projectedSpend == Decimal(100) * 31 / 15)
        #expect(forecast.daysLeft == 16)
    }

    @Test func aProjectionOverTheBudgetIsFlagged() throws {
        let forecast = try #require(ForecastCalculator.forecast(
            for: overview(spent: "300"),
            today: CalendarDate(year: 2026, month: 8, day: 15)))
        #expect(forecast.isProjectedOver)
        #expect(forecast.projectedRemaining < 0)
    }

    @Test func stayingUnderTheBudgetIsNotFlagged() throws {
        let forecast = try #require(ForecastCalculator.forecast(
            for: overview(spent: "100"),
            today: CalendarDate(year: 2026, month: 8, day: 25)))
        #expect(forecast.isProjectedOver == false)
        #expect(forecast.projectedRemaining > 0)
    }

    @Test func theFirstDaysAreMarkedUnreliable() throws {
        let early = try #require(ForecastCalculator.forecast(
            for: overview(spent: "80"), today: CalendarDate(year: 2026, month: 8, day: 2)))
        #expect(early.isReliable == false)

        let later = try #require(ForecastCalculator.forecast(
            for: overview(spent: "80"), today: CalendarDate(year: 2026, month: 8, day: 9)))
        #expect(later.isReliable)
    }

    @Test func onTheLastDayTheProjectionIsJustTheActual() throws {
        let forecast = try #require(ForecastCalculator.forecast(
            for: overview(spent: "217"),
            today: CalendarDate(year: 2026, month: 8, day: 31)))
        #expect(forecast.projectedSpend == 217)
        #expect(forecast.daysLeft == 0)
    }

    @Test func onlyTheRunningMonthGetsAProjection() throws {
        // A finished month needs no forecast…
        #expect(ForecastCalculator.forecast(
            for: overview(spent: "100"),
            today: CalendarDate(year: 2026, month: 9, day: 3)) == nil)
        // …and a future one has nothing to project from.
        #expect(ForecastCalculator.forecast(
            for: overview(spent: "100"),
            today: CalendarDate(year: 2026, month: 7, day: 3)) == nil)
    }

    @Test func outstandingFixedCostsRideAlongSeparately() throws {
        let forecast = try #require(ForecastCalculator.forecast(
            for: overview(spent: "100", rentExpected: 1250),
            today: CalendarDate(year: 2026, month: 8, day: 15)))
        #expect(forecast.outstandingFixed == 1250)
        // Fixed costs are their own section and must not be folded into the budget run rate.
        #expect(forecast.projectedSpend == Decimal(100) * 31 / 15)
    }

    @Test func aPaidFixedCostNoLongerCountsAsOutstanding() throws {
        let forecast = try #require(ForecastCalculator.forecast(
            for: overview(spent: "100", rentExpected: 1250, rentBooked: "1250"),
            today: CalendarDate(year: 2026, month: 8, day: 15)))
        #expect(forecast.outstandingFixed == 0)
    }

    @Test func spendingNothingProjectsToNothing() throws {
        let forecast = try #require(ForecastCalculator.forecast(
            for: overview(spent: "0"), today: CalendarDate(year: 2026, month: 8, day: 15)))
        #expect(forecast.projectedSpend == 0)
        #expect(forecast.projectedRemaining == 400)
    }

    @Test func februaryUsesItsOwnLength() throws {
        let overview = BudgetCalculator.overview(
            month: YearMonth(year: 2026, month: 2), transactions: [], categories: [],
            budgets: [:], categorizer: Categorizer(rules: []))
        let forecast = try #require(ForecastCalculator.forecast(
            for: overview, today: CalendarDate(year: 2026, month: 2, day: 10)))
        #expect(forecast.daysInMonth == 28)
    }
}

struct TrendTests {
    let groceries = BudgetCategory(name: "Lebensmittel", kind: .spending, sortIndex: 0)
    let august = YearMonth(year: 2026, month: 8)

    private var categorizer: Categorizer {
        Categorizer(rules: [Rule(categoryID: groceries.id, matcher: .mcc("5411"))])
    }

    private func booking(_ month: Int, _ day: Int, _ amount: String, _ id: String) -> Transaction {
        Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "-\(amount)",
                      date: CalendarDate(year: 2026, month: month, day: day), id: id)
    }

    @Test func theAverageCoversTheThreeMonthsBefore() throws {
        let transactions = [
            // April is four months back, so it must stay out of the average entirely.
            booking(4, 5, "999", "apr"),
            booking(6, 5, "100", "jun"),
            booking(7, 5, "200", "jul"),
            booking(8, 5, "139", "aug"),
        ]
        let comparison = try #require(TrendCalculator.comparison(
            for: groceries.id, month: august, transactions: transactions,
            categorizer: categorizer))

        #expect(comparison.current == 139)
        // The window is July, June and May; May has no bookings at all, so it is not a zero.
        #expect(comparison.monthsCompared == 2)
        #expect(comparison.average == 150)
        #expect(comparison.isAbove == false)
    }

    @Test func monthsTheExportDoesNotCoverAreNotCountedAsZero() throws {
        // Only July has history. Averaging over three months would report 66 € instead of 200.
        let transactions = [
            booking(7, 5, "200", "jul"),
            booking(8, 5, "100", "aug"),
        ]
        let comparison = try #require(TrendCalculator.comparison(
            for: groceries.id, month: august, transactions: transactions,
            categorizer: categorizer))
        #expect(comparison.monthsCompared == 1)
        #expect(comparison.average == 200)
        #expect(comparison.delta == -100)
    }

    @Test func aMonthWithBookingsButNoneInThisCategoryCountsAsZero() throws {
        let transactions = [
            // July has activity, just not groceries — that is a real zero.
            Fixtures.card(merchant: "Alte Utting", mcc: "5812", amount: "-40",
                          date: CalendarDate(year: 2026, month: 7, day: 5), id: "jul"),
            booking(6, 5, "200", "jun"),
            booking(8, 5, "100", "aug"),
        ]
        let comparison = try #require(TrendCalculator.comparison(
            for: groceries.id, month: august, transactions: transactions,
            categorizer: categorizer))
        #expect(comparison.monthsCompared == 2)
        #expect(comparison.average == 100)
    }

    @Test func spendingMoreThanUsualIsReported() throws {
        let transactions = [
            booking(7, 5, "100", "jul"),
            booking(8, 5, "250", "aug"),
        ]
        let comparison = try #require(TrendCalculator.comparison(
            for: groceries.id, month: august, transactions: transactions,
            categorizer: categorizer))
        #expect(comparison.isAbove)
        #expect(comparison.delta == 150)
    }

    @Test func withoutAnyHistoryThereIsNothingToCompare() throws {
        let comparison = TrendCalculator.comparison(
            for: groceries.id, month: august,
            transactions: [booking(8, 5, "100", "aug")], categorizer: categorizer)
        #expect(comparison == nil)
    }

    @Test func aRefundLowersTheMonthItBelongsTo() throws {
        let transactions = [
            booking(7, 5, "100", "jul"),
            booking(8, 5, "100", "aug"),
            Fixtures.card(merchant: "EDEKA", mcc: "5411", amount: "30",
                          date: CalendarDate(year: 2026, month: 8, day: 9), id: "refund"),
        ]
        let comparison = try #require(TrendCalculator.comparison(
            for: groceries.id, month: august, transactions: transactions,
            categorizer: categorizer))
        #expect(comparison.current == 70)
    }
}
