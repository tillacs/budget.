import Foundation
import Testing
@testable import money_

/// End-to-end over the real path the Import button takes: read the file off disk, parse it,
/// merge it, persist it, and rebuild the categorizer. Only the document picker is left out.
@MainActor
struct AppStoreImportTests {
    private func writeCSV(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString).csv")
        try #require(text.data(using: .utf8)).write(to: url)
        return url
    }

    @Test func importingAFileFillsTheStoreAndSurvivesARelaunch() async throws {
        let file = DataFile.temporary()
        let url = try writeCSV(CSVFixtures.export)
        defer { file.removeDirectory(); try? FileManager.default.removeItem(at: url) }

        let store = AppStore(data: .seeded(), file: file)
        await store.importTransactions(from: url)

        #expect(store.importErrorMessage == nil)
        #expect(store.data.transactions.count == CSVFixtures.rowCount)
        #expect(store.lastImport?.added == CSVFixtures.rowCount)

        // What a cold launch would see.
        let relaunched = AppStore.loadFromDisk(file: file)
        #expect(relaunched.data.transactions.count == CSVFixtures.rowCount)
        #expect(relaunched.data.categories.count == DefaultSetup.seeds.count)
    }

    @Test func importingTheSameFileAgainAddsNothing() async throws {
        let file = DataFile.temporary()
        let url = try writeCSV(CSVFixtures.export)
        defer { file.removeDirectory(); try? FileManager.default.removeItem(at: url) }

        let store = AppStore(data: .seeded(), file: file)
        await store.importTransactions(from: url)
        await store.importTransactions(from: url)

        #expect(store.data.transactions.count == CSVFixtures.rowCount)
        #expect(store.lastImport?.added == 0)
        #expect(store.lastImport?.unchanged == CSVFixtures.rowCount)
    }

    @Test func aBrokenHeaderReportsTheColumnAndChangesNothing() async throws {
        let file = DataFile.temporary()
        let good = try writeCSV(CSVFixtures.export)
        let broken = try writeCSV(CSVFixtures.csv(
            header: CSVFixtures.header.replacingOccurrences(of: #""mcc_code""#, with: #""mcc""#),
            rows: [CSVFixtures.baseRow]))
        defer {
            file.removeDirectory()
            try? FileManager.default.removeItem(at: good)
            try? FileManager.default.removeItem(at: broken)
        }

        let store = AppStore(data: .seeded(), file: file)
        await store.importTransactions(from: good)
        let before = store.data.transactions

        await store.importTransactions(from: broken)

        let message = try #require(store.importErrorMessage)
        #expect(message.contains("mcc_code"))
        // A failed import must not half-apply.
        #expect(store.data.transactions == before)
    }

    @Test func theDefaultRulesCategorizeTheImportImmediately() async throws {
        let file = DataFile.temporary()
        let url = try writeCSV(CSVFixtures.export)
        defer { file.removeDirectory(); try? FileManager.default.removeItem(at: url) }

        let store = AppStore(data: .seeded(), file: file)
        await store.importTransactions(from: url)

        let groceries = try #require(store.data.categories.first { $0.name == "Lebensmittel" })
        let edeka = try #require(store.data.transactions.first {
            $0.id == "019fccaa-5ffe-74ba-abbb-969255669474"
        })
        #expect(store.categorizer.assignment(for: edeka).categoryID == groceries.id)
    }

    @Test func resettingWipesTheBookingsAndReseedsTheDefaults() async throws {
        let file = DataFile.temporary()
        let url = try writeCSV(CSVFixtures.export)
        defer { file.removeDirectory(); try? FileManager.default.removeItem(at: url) }

        let store = AppStore(data: .seeded(), file: file)
        await store.importTransactions(from: url)
        store.resetAllData()

        #expect(store.data.transactions.isEmpty)
        #expect(store.data.categories.count == DefaultSetup.seeds.count)
        #expect(AppStore.loadFromDisk(file: file).data.transactions.isEmpty)
    }

    @Test func theUsersOwnNumbersSurviveTheNextImport() async throws {
        let file = DataFile.temporary()
        let url = try writeCSV(CSVFixtures.export)
        defer { file.removeDirectory(); try? FileManager.default.removeItem(at: url) }

        let store = AppStore(data: .seeded(), file: file)
        let groceries = try #require(store.data.categories.first { $0.name == "Lebensmittel" })
        store.setBudget(Decimal(string: "412.50")!, for: groceries.id)

        await store.importTransactions(from: url)

        // The CSV owns bookings; it must never touch the user's own numbers.
        #expect(store.data.budgets[groceries.id] == Decimal(string: "412.50")!)
        #expect(AppStore.loadFromDisk(file: file).data.budgets[groceries.id]
                == Decimal(string: "412.50")!)
    }

    @Test func anUnreadableFileIsReportedNotSwallowed() async throws {
        let file = DataFile.temporary()
        defer { file.removeDirectory() }

        let store = AppStore(data: .seeded(), file: file)
        await store.importTransactions(
            from: FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist.csv"))

        #expect(store.importErrorMessage != nil)
        #expect(store.data.transactions.isEmpty)
    }
}
