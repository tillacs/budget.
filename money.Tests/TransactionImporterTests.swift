import Foundation
import Testing
@testable import money_

struct TransactionImporterTests {
    private func parsed() throws -> [Transaction] {
        try TransactionCSVParser.parse(CSVFixtures.export).transactions
    }

    // MARK: Idempotence

    @Test func aFirstImportAddsEverything() throws {
        let (merged, summary) = TransactionImporter.merge(existing: [], incoming: try parsed())
        #expect(merged.count == CSVFixtures.rowCount)
        #expect(summary.added == CSVFixtures.rowCount)
        #expect(summary.updated == 0)
        #expect(summary.unchanged == 0)
        #expect(summary.parsed == CSVFixtures.rowCount)
    }

    @Test func importingTheSameFileTwiceChangesNothing() throws {
        let transactions = try parsed()
        let first = TransactionImporter.merge(existing: [], incoming: transactions)
        let second = TransactionImporter.merge(existing: first.transactions, incoming: transactions)

        #expect(second.transactions == first.transactions)
        #expect(second.summary.added == 0)
        #expect(second.summary.updated == 0)
        #expect(second.summary.unchanged == CSVFixtures.rowCount)
    }

    @Test func tenImportsInARowStillConverge() throws {
        let transactions = try parsed()
        var stored: [Transaction] = []
        for _ in 0..<10 {
            stored = TransactionImporter.merge(existing: stored, incoming: transactions).transactions
        }
        #expect(stored.count == CSVFixtures.rowCount)
        #expect(Set(stored.map(\.id)).count == CSVFixtures.rowCount)
    }

    @Test func anOverlappingExportOnlyAddsWhatIsNew() throws {
        let transactions = try parsed()
        let older = Array(transactions.prefix(6))
        let overlapping = Array(transactions.suffix(8))

        let first = TransactionImporter.merge(existing: [], incoming: older)
        let second = TransactionImporter.merge(existing: first.transactions, incoming: overlapping)

        #expect(second.summary.added == CSVFixtures.rowCount - 6)
        #expect(second.summary.unchanged == 8 - (CSVFixtures.rowCount - 6))
        #expect(second.transactions.count == CSVFixtures.rowCount)
    }

    @Test func aFullHistoryOverAPartialOneDoesNotDuplicate() throws {
        let transactions = try parsed()
        let partial = TransactionImporter.merge(existing: [], incoming: Array(transactions.suffix(3)))
        let full = TransactionImporter.merge(existing: partial.transactions, incoming: transactions)

        #expect(full.transactions.count == CSVFixtures.rowCount)
        #expect(full.summary.unchanged == 3)
        #expect(full.summary.added == CSVFixtures.rowCount - 3)
    }

    @Test func aRowRepeatedInsideOneFileCountsOnce() throws {
        let transactions = try parsed()
        let doubled = transactions + transactions
        let (merged, summary) = TransactionImporter.merge(existing: [], incoming: doubled)

        #expect(merged.count == CSVFixtures.rowCount)
        #expect(summary.parsed == CSVFixtures.rowCount)
        #expect(summary.added == CSVFixtures.rowCount)
    }

    // MARK: The CSV wins

    @Test func aRestatedBookingIsOverwrittenNotDuplicated() throws {
        let transactions = try parsed()
        let original = try #require(transactions.first)
        let corrected = Transaction(
            id: original.id, timestamp: original.timestamp, bookingDate: original.bookingDate,
            account: original.account, type: original.type, merchant: original.merchant,
            detail: original.detail,
            amount: TransactionCSVParser.decimal(from: "-99.99")!,
            fee: original.fee, tax: original.tax, currency: original.currency,
            originalAmount: nil, originalCurrency: nil, fxRate: nil, counterpartyName: nil,
            counterpartyIBAN: nil, paymentReference: nil, mcc: original.mcc)

        let stored = TransactionImporter.merge(existing: [], incoming: transactions).transactions
        let (merged, summary) = TransactionImporter.merge(existing: stored, incoming: [corrected])

        #expect(merged.count == CSVFixtures.rowCount)
        #expect(summary.updated == 1)
        #expect(summary.added == 0)
        #expect(merged.first { $0.id == original.id }?.amount == Decimal(string: "-99.99")!)
    }

    // MARK: Ordering and reporting

    @Test func theResultIsOrderedRegardlessOfInputOrder() throws {
        let transactions = try parsed()
        let forward = TransactionImporter.merge(existing: [], incoming: transactions).transactions
        let backward = TransactionImporter.merge(existing: [], incoming: transactions.reversed()).transactions
        #expect(forward == backward)
        #expect(forward == forward.sorted {
            $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
        })
    }

    @Test func theSummaryReportsTheDateRangeOfTheFile() throws {
        let (_, summary) = TransactionImporter.merge(existing: [], incoming: try parsed())
        #expect(summary.earliest == CalendarDate(year: 2024, month: 5, day: 15))
        #expect(summary.latest == CalendarDate(year: 2026, month: 8, day: 14))
    }

    @Test func anEmptyImportIsHarmless() throws {
        let stored = TransactionImporter.merge(existing: [], incoming: try parsed()).transactions
        let (merged, summary) = TransactionImporter.merge(existing: stored, incoming: [])
        #expect(merged == stored)
        #expect(summary == ImportSummary.empty)
    }
}

struct AppDataPersistenceTests {
    @Test func everythingSurvivesARoundTrip() throws {
        let groceries = BudgetCategory(name: "Lebensmittel")
        let data = AppData(
            transactions: try TransactionCSVParser.parse(CSVFixtures.export).transactions,
            categories: [groceries],
            rules: [Rule(categoryID: groceries.id, matcher: .mcc("5411")),
                    Rule(categoryID: groceries.id, matcher: .pattern(Pattern("EDEKA", field: .detail, kind: .regex)))],
            budgets: [groceries.id: Decimal(string: "412.50")!],
            overrides: ["tx-1": groceries.id],
            sort: .manual)

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(AppData.self, from: encoded)

        #expect(decoded.transactions == data.transactions)
        #expect(decoded.categories == data.categories)
        #expect(decoded.rules == data.rules)
        #expect(decoded.overrides == data.overrides)
        #expect(decoded.sort == .manual)
        // The one that would quietly rot if it ever went through Double.
        #expect(decoded.budgets[groceries.id] == Decimal(string: "412.50")!)
    }

    @Test func aSeededStoreIsUsableBeforeAnyImport() throws {
        let data = AppData.seeded()
        #expect(data.transactions.isEmpty)
        #expect(data.categories.count == DefaultSetup.seeds.count)
        #expect(!data.rules.isEmpty)
        #expect(data.schemaVersion == AppData.currentSchemaVersion)
    }
}
