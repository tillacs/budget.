import Foundation
import Testing
@testable import money_

/// Der gemeinsame Maßstab beider Ringe ist die einzige Rechnung, die diese App noch
/// hat — und die, an der man am ehesten etwas kaputt macht.
struct MonthSummaryTests {
    private let month = YearMonth(year: 2026, month: 9)

    private func fixture() -> ([BudgetCategory], [Entry]) {
        let essen = BudgetCategory(name: "Essen", tint: .azure, direction: .expense)
        let wohnen = BudgetCategory(name: "Wohnen", tint: .indigo, direction: .expense)
        let gehalt = BudgetCategory(name: "Gehalt", tint: .mint, direction: .income)

        let entries = [
            entry(300, essen, day: 3),
            entry(100, essen, day: 9),
            entry(600, wohnen, day: 1),
            entry(2000, gehalt, day: 1),
        ]
        return ([essen, wohnen, gehalt], entries)
    }

    private func entry(
        _ amount: Int, _ category: BudgetCategory, day: Int, month: Int = 9
    ) -> Entry {
        Entry(
            date: CalendarDate(year: 2026, month: month, day: day),
            amount: Decimal(amount),
            direction: category.direction,
            categoryID: category.id)
    }

    @Test func derGrößereRingFülltDenKreisGanz() {
        let (categories, entries) = fixture()
        let summary = MonthSummary.make(month: month, entries: entries, categories: categories)

        #expect(summary.expenses.total == 1000)
        #expect(summary.income.total == 2000)
        #expect(summary.sweep(.income) == 1)
        #expect(summary.sweep(.expense) == 0.5)
    }

    @Test func dieLückeImKürzerenRingIstDerÜberschuss() {
        let (categories, entries) = fixture()
        let summary = MonthSummary.make(month: month, entries: entries, categories: categories)

        #expect(summary.net == 1000)
        let offen = 1 - summary.sweep(.expense)
        #expect(abs(offen - (summary.net / summary.scale).doubleValue) < 0.000_001)
    }

    @Test func segmenteStehenAbsteigendUndTeilenSichDenRing() throws {
        let (categories, entries) = fixture()
        let summary = MonthSummary.make(month: month, entries: entries, categories: categories)

        #expect(summary.expenses.slices.map(\.category.name) == ["Wohnen", "Essen"])
        #expect(summary.expenses.slices.first?.share == 0.6)
        #expect(abs(summary.expenses.slices.map(\.share).reduce(0, +) - 1) < 1e-12)

        let essen = try #require(summary.expenses.slices.last)
        #expect(essen.count == 2)
        #expect(essen.total == 400)
    }

    @Test func einAndererMonatZähltNichtMit() {
        let (categories, _) = fixture()
        let august = entry(999, categories[0], day: 4, month: 8)
        let summary = MonthSummary.make(month: month, entries: [august], categories: categories)

        #expect(summary.isEmpty)
        #expect(summary.sweep(.expense) == 0)
    }

    /// Eine Buchung ohne Kategorie darf keinen Ring aufblähen — sonst stünde in der
    /// Mitte eine Summe, zu der es keine Zeile gibt.
    @Test func buchungOhneKategorieBleibtDraußen() {
        let (categories, entries) = fixture()
        let waise = Entry(
            date: CalendarDate(year: 2026, month: 9, day: 5),
            amount: 500, direction: .expense, categoryID: UUID())

        let summary = MonthSummary.make(
            month: month, entries: entries + [waise], categories: categories)
        #expect(summary.expenses.total == 1000)
    }

    @Test func leererMonatHatKeineAnteile() {
        let summary = MonthSummary.make(month: month, entries: [], categories: [])
        #expect(summary.isEmpty)
        #expect(summary.net == 0)
        #expect(summary.sweep(.income) == 0)
    }
}

struct EntryTests {
    /// Das Vorzeichen steckt in der Richtung, nie im Betrag.
    @Test func betragBleibtPositiv() {
        let entry = Entry(amount: -12, direction: .expense, categoryID: UUID())
        #expect(entry.amount == 0)
    }

    @Test func vorzeichenKommtAusDerRichtung() {
        let id = UUID()
        #expect(Entry(amount: 10, direction: .expense, categoryID: id).signedAmount == -10)
        #expect(Entry(amount: 10, direction: .income, categoryID: id).signedAmount == 10)
    }
}
