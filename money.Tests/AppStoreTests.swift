import Foundation
import Testing
@testable import money_

@MainActor
struct AppStoreTests {
    private func store() -> AppStore {
        AppStore(data: .seeded(), file: DataFile(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("budget-test-\(UUID().uuidString).json")))
    }

    private func category(_ store: AppStore, _ name: String) throws -> BudgetCategory {
        try #require(store.data.categories.first { $0.name == name })
    }

    /// Der Kern der Schnellerfassung: Nach dem Doppeltipp muss die zuletzt benutzte
    /// Kategorie schon stehen.
    @Test func zuletztBenutzteKategorieWirdVorausgewählt() throws {
        let store = store()
        let unterwegs = try category(store, "Unterwegs")
        store.add(Entry(amount: 12, direction: .expense, categoryID: unterwegs.id))

        #expect(store.data.preferredCategory(for: .expense)?.id == unterwegs.id)
        // Die andere Seite bleibt davon unberührt.
        #expect(store.data.preferredCategory(for: .income)?.name == "Gehalt")
    }

    @Test func ohneVorgeschichteStehtDieErsteKategorieDa() throws {
        let store = store()
        #expect(store.data.preferredCategory(for: .expense)?.name == "Essen")
    }

    @Test func löschenNimmtDieBuchungenMit() throws {
        let store = store()
        let essen = try category(store, "Essen")
        let wohnen = try category(store, "Wohnen")
        store.add(Entry(amount: 10, direction: .expense, categoryID: essen.id))
        store.add(Entry(amount: 20, direction: .expense, categoryID: wohnen.id))

        store.deleteCategory(essen.id)

        #expect(store.data.entries.count == 1)
        #expect(store.data.entries.first?.categoryID == wohnen.id)
        #expect(store.data.lastUsed["expense"] == wohnen.id)
    }

    /// Dreht eine Kategorie die Seite, müssen ihre Buchungen mitgehen — sonst lägen
    /// Beträge in einem Ring, zu dem ihre Kategorie nicht mehr gehört.
    @Test func seitenwechselZiehtDieBuchungenMit() throws {
        let store = store()
        var sonstiges = try category(store, "Sonstiges")
        store.add(Entry(amount: 50, direction: .income, categoryID: sonstiges.id))

        sonstiges.direction = .expense
        store.updateCategory(sonstiges)

        #expect(store.data.entries.allSatisfy { $0.direction == .expense })
        let summary = store.summary(for: .current())
        #expect(summary.income.total == 0)
        #expect(summary.expenses.total == 50)
    }

    @Test func sortierenBetrifftNurDieEigeneSeite() throws {
        let store = store()
        let vorherEinnahmen = store.data.categories(for: .income).map(\.name)

        store.moveCategories(for: .expense, from: IndexSet(integer: 0), to: 3)

        #expect(store.data.categories(for: .expense).map(\.name).first == "Lebensmittel")
        #expect(store.data.categories(for: .expense).map(\.name)[2] == "Essen")
        #expect(store.data.categories(for: .income).map(\.name) == vorherEinnahmen)
    }

    @Test func ändernEinerBuchungRechnetDenMonatNeu() throws {
        let store = store()
        let essen = try category(store, "Essen")
        let entry = Entry(amount: 10, direction: .expense, categoryID: essen.id)
        store.add(entry)

        var geändert = entry
        geändert.amount = 30
        store.update(geändert)

        #expect(store.summary(for: .current()).expenses.total == 30)

        store.deleteEntry(entry.id)
        #expect(store.summary(for: .current()).isEmpty)
    }
}

@MainActor
struct DataFileTests {
    private var temporary: DataFile {
        DataFile(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("budget-file-\(UUID().uuidString).json"))
    }

    @Test func gespeichertesKommtUnverändertZurück() throws {
        let file = temporary
        defer { try? file.delete() }

        let store = AppStore(data: .seeded(), file: file)
        let essen = try #require(store.data.categories.first)
        store.add(Entry(
            amount: Decimal(string: "12.34")!, direction: .expense,
            categoryID: essen.id, note: "Mittag"))

        let geladen = try #require(try file.load())
        #expect(geladen.schemaVersion == AppData.currentSchemaVersion)
        #expect(geladen.entries.count == 1)
        // Beträge sind `Decimal` und bleiben es — auch über die Datei hinweg.
        #expect(geladen.entries[0].amount == Decimal(string: "12.34"))
        #expect(geladen.entries[0].note == "Mittag")
    }

    /// Die alte Import-Datei (Schema 1) lässt sich nicht lesen. Sie darf die App nicht
    /// blockieren, sondern wird verworfen.
    @Test func unlesbareDateiFührtZumFrischenStart() throws {
        let file = temporary
        defer { try? file.delete() }
        try FileManager.default.createDirectory(
            at: file.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":1,"transactions":[]}"#.utf8).write(to: file.fileURL)

        let store = AppStore.loadFromDisk(file: file)
        #expect(store.data.entries.isEmpty)
        #expect(!store.data.categories.isEmpty)
    }
}

@MainActor
struct QuickEntryRouterTests {
    /// Zweimal dieselbe Richtung muss zweimal wirken — sonst bliebe der zweite
    /// Doppeltipp auf die Rückseite folgenlos.
    @Test func jedeAnforderungZähltEinzeln() {
        let router = QuickEntryRouter.shared
        _ = router.consume()

        let vorher = router.token
        router.request(.expense)
        router.request(.expense)

        #expect(router.token == vorher + 2)
        #expect(router.consume() == .expense)
        // Abgeholt ist abgeholt.
        #expect(router.consume() == nil)
    }
}

@MainActor
struct MerchantMemoryTests {
    private func store() -> AppStore {
        AppStore(data: .seeded(), file: DataFile(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("budget-merchant-\(UUID().uuidString).json")))
    }

    /// Der Kern der Automation: Was einmal bestätigt wurde, wird nicht neu gefragt.
    @Test func merktSichDieKategorieEinesHändlers() throws {
        let store = store()
        let lebensmittel = try #require(store.data.categories.first { $0.name == "Lebensmittel" })

        store.add(
            Entry(amount: 12, direction: .expense, categoryID: lebensmittel.id),
            merchant: "REWE")

        #expect(store.rememberedCategory(forMerchant: "rewe")?.id == lebensmittel.id)
        #expect(store.rememberedCategory(forMerchant: " REWE ")?.id == lebensmittel.id)
        #expect(store.rememberedCategory(forMerchant: "Aldi") == nil)
    }

    /// Auch die Notiz einer von Hand erfassten Buchung ist eine Aussage über den Händler.
    @Test func lerntAuchAusDerNotiz() throws {
        let store = store()
        let essen = try #require(store.data.categories.first { $0.name == "Essen" })

        store.add(Entry(amount: 8, direction: .expense, categoryID: essen.id, note: "Bäckerei"))
        #expect(store.rememberedCategory(forMerchant: "bäckerei")?.id == essen.id)
    }

    /// Eine Zuordnung auf eine gelöschte Kategorie würde stumm ins Leere zeigen.
    @Test func vergisstGelöschteKategorien() throws {
        let store = store()
        let abos = try #require(store.data.categories.first { $0.name == "Abos" })

        store.add(Entry(amount: 12, direction: .expense, categoryID: abos.id), merchant: "Netflix")
        store.deleteCategory(abos.id)

        #expect(store.rememberedCategory(forMerchant: "Netflix") == nil)
        #expect(store.data.merchantCategories.isEmpty)
    }

    /// Ein neues Feld darf keine bestehende Datei unlesbar machen — sonst stünde der
    /// Nutzer beim nächsten Update vor einer leeren App.
    @Test func liestEineDateiOhneDasNeueFeld() throws {
        let file = DataFile(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("budget-alt-\(UUID().uuidString).json"))
        defer { try? file.delete() }

        try FileManager.default.createDirectory(
            at: file.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let alt = #"{"schemaVersion":2,"entries":[],"categories":[],"lastUsed":{}}"#
        try Data(alt.utf8).write(to: file.fileURL)

        let loaded = try #require(try file.load())
        #expect(loaded.merchantCategories.isEmpty)
        #expect(loaded.schemaVersion == 2)
    }
}
