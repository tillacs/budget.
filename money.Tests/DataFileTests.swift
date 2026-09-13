import Foundation
import Testing
@testable import money_

extension DataFile {
    /// A private file per test, so nothing races and nothing touches the real container.
    static func temporary() -> DataFile {
        DataFile(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("money-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("data.json"))
    }

    func removeDirectory() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }
}

struct DataFileTests {
    @Test func savingAndReloadingKeepsEveryDecision() throws {
        let file = DataFile.temporary()
        defer { file.removeDirectory() }

        let category = BudgetCategory(name: "Lebensmittel", kind: .spending, sortIndex: 3)
        var data = AppData.seeded()
        data.categories.append(category)
        data.budgets[category.id] = Decimal(string: "412.50")!
        data.transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        data.sort = .manual

        try file.save(data)
        let reloaded = try #require(try file.load())

        #expect(reloaded.transactions.count == CSVFixtures.rowCount)
        #expect(reloaded.budgets[category.id] == Decimal(string: "412.50")!)
        #expect(reloaded.sort == .manual)
        #expect(reloaded.categories.contains(category))
    }

    @Test func nothingSavedMeansNothingLoaded() throws {
        let file = DataFile.temporary()
        defer { file.removeDirectory() }
        #expect(try file.load() == nil)
    }

    @Test func deletingLeavesNothingBehind() throws {
        let file = DataFile.temporary()
        defer { file.removeDirectory() }

        try file.save(.seeded())
        #expect(try file.load() != nil)
        try file.delete()
        #expect(try file.load() == nil)
    }

    @MainActor
    @Test func aCorruptFileDoesNotBrickTheApp() throws {
        let file = DataFile.temporary()
        defer { file.removeDirectory() }

        try FileManager.default.createDirectory(
            at: file.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #require("{ not json".data(using: .utf8)).write(to: file.fileURL)

        // Rather than crash-looping on launch, the store starts clean.
        let store = AppStore.loadFromDisk(file: file)
        #expect(store.data.transactions.isEmpty)
        #expect(store.data.categories.count == DefaultSetup.seeds.count)
    }

    // MARK: Encodings

    @Test func aLatin1FileWithUmlautsIsStillReadable() throws {
        let csv = CSVFixtures.csv(rows: [CSVFixtures.row([.name: "EDEKA München"])])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("latin1-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        try #require(csv.data(using: .isoLatin1)).write(to: url)
        let transaction = try #require(
            try TransactionCSVParser.parse(try DataFile.readText(at: url)).transactions.first)
        #expect(transaction.merchant == "EDEKA München")
    }

    @Test func aUTF8FileIsReadUnchanged() throws {
        let csv = CSVFixtures.csv(rows: [CSVFixtures.row([.name: "Ihle Bäckerei Grünwald"])])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("utf8-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        try #require(csv.data(using: .utf8)).write(to: url)
        let transaction = try #require(
            try TransactionCSVParser.parse(try DataFile.readText(at: url)).transactions.first)
        #expect(transaction.merchant == "Ihle Bäckerei Grünwald")
    }
}
