// AppStore.swift
// budget. — der einzige veränderliche Zustand der App

import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    private(set) var data: AppData

    /// Steigt bei jeder Änderung. Die Oberfläche hängt ihre Haptik daran, statt an
    /// jeder einzelnen Mutation.
    private(set) var revision = 0

    var saveErrorMessage: String?

    /// Die zuletzt gesicherte Buchung, mit einem Zähler daneben. Die Oberfläche hängt
    /// ihre Bestätigungsanimation daran — der Zähler, damit zweimal derselbe Betrag
    /// auch zweimal animiert.
    private(set) var lastSaved: Entry?
    private(set) var saveTick = 0

    /// Der letzte Import, für die Zusammenfassung nach dem Teilen.
    private(set) var lastReport: ImportReport?
    private(set) var reportTick = 0

    private let file: DataFile

    init(data: AppData, file: DataFile = .applicationDefault) {
        self.data = data
        self.file = file
    }

    static func loadFromDisk(file: DataFile = .applicationDefault) -> AppStore {
        do {
            if let stored = try file.load() { return AppStore(data: stored, file: file) }
        } catch {
            // Eine unlesbare Datei darf die App nicht blockieren. Das gilt auch für die
            // alte Import-Datei aus Schema 1: Sie enthält nichts, was sich in Buchungen
            // übersetzen ließe, also wird sie verworfen statt migriert.
            try? file.delete()
        }
        let store = AppStore(data: .seeded(), file: file)
        store.persist()
        return store
    }

    // MARK: - Auswertung

    func summary(for month: YearMonth) -> MonthSummary {
        MonthSummary.make(month: month, entries: data.entries, categories: data.categories)
    }

    func entries(of category: UUID, in month: YearMonth) -> [Entry] {
        data.entries.of(category: category, in: month)
    }

    /// Monate, in denen etwas steht — plus der laufende, damit man immer irgendwo steht.
    func recordedMonths(including month: YearMonth) -> Set<YearMonth> {
        data.entries.recordedMonths.union([month, .current()])
    }

    var proposals: [Entry] { data.proposals }
    var hasProposals: Bool { data.entries.contains { $0.status == .proposed } }

    func entry(_ id: UUID?) -> Entry? {
        guard let id else { return nil }
        return data.entries.first { $0.id == id }
    }

    // MARK: - Buchungen

    func add(_ entry: Entry, merchant: String? = nil) {
        data.entries.append(entry)
        data.lastUsed[entry.direction.rawValue] = entry.categoryID
        learn(merchant ?? entry.note, as: entry.categoryID)
        mark(entry)
        persist()
    }

    /// Merkt sich, welche Kategorie zu einem Händler gehört.
    ///
    /// Gelernt wird auch aus der Notiz einer von Hand erfassten Buchung: Wer „REWE" in
    /// die Notiz tippt und Lebensmittel wählt, hat damit dieselbe Aussage getroffen wie
    /// ein Vorschlag. Falsch liegen kann die Tabelle nicht folgenschwer — sie schlägt
    /// nur vor, gebucht wird erst nach Bestätigung.
    func learn(_ merchant: String?, as category: UUID) {
        guard let merchant, let key = MerchantKey.normalized(merchant) else { return }
        data.memory.confirm(
            Signals(merchantKey: key, tokens: MerchantKey.tokens(merchant)), as: category)
    }

    func rememberedCategory(forMerchant merchant: String) -> BudgetCategory? {
        data.rememberedCategory(forMerchant: merchant)
    }

    func update(_ entry: Entry) {
        guard let index = data.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let before = data.entries[index]
        data.entries[index] = entry
        data.lastUsed[entry.direction.rawValue] = entry.categoryID
        if before.categoryID != entry.categoryID, entry.source == .tradeRepublic {
            // Eine Umkategorisierung ist die deutlichste Aussage, die es gibt.
            data.memory.correct(entry.signals, from: before.categoryID, to: entry.categoryID)
        } else {
            learn(entry.merchant ?? entry.note, as: entry.categoryID)
        }
        mark(entry)
        persist()
    }

    func deleteEntry(_ id: UUID) {
        if let entry = data.entries.first(where: { $0.id == id }), let external = entry.externalID {
            data.ignoredExternalIDs.append(external)
        }
        data.entries.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Posteingang

    /// Den Vorschlag annehmen, wie er ist.
    func accept(_ id: UUID) {
        guard let index = data.entries.firstIndex(where: { $0.id == id }),
              data.entries[index].status == .proposed else { return }
        var entry = data.entries[index]
        entry.status = .confirmed
        entry.suggestion?.decision = .accepted
        data.entries[index] = entry
        data.lastUsed[entry.direction.rawValue] = entry.categoryID
        if entry.kind != .transfer { data.memory.confirm(entry.signals, as: entry.categoryID) }
        settleRefunds(of: entry.id, to: entry.categoryID)
        persist()
    }

    /// Erstattungen, die an dieser Buchung hängen, übernehmen ihre Entscheidung.
    private func settleRefunds(of original: UUID, to category: UUID) {
        for i in data.entries.indices where data.entries[i].refundOf == original {
            data.entries[i].categoryID = category
            if data.entries[i].status == .proposed { data.entries[i].status = .autoBooked }
        }
    }

    /// Eine andere Kategorie als vorgeschlagen — für Vorschläge wie für Gebuchtes.
    func correct(_ id: UUID, to category: UUID) {
        guard let index = data.entries.firstIndex(where: { $0.id == id }),
              let chosen = data.category(category) else { return }
        var entry = data.entries[index]
        let proposed = entry.suggestion?.categoryID ?? entry.categoryID
        entry.categoryID = chosen.id
        entry.direction = chosen.direction
        entry.kind = entry.kind == .transfer ? .flow : entry.kind
        entry.status = .confirmed
        entry.suggestion?.decision = proposed == chosen.id ? .accepted : .corrected(chosen.id)
        data.entries[index] = entry
        data.lastUsed[entry.direction.rawValue] = chosen.id
        data.memory.correct(entry.signals, from: proposed, to: chosen.id)
        settleRefunds(of: entry.id, to: chosen.id)
        persist()
    }

    enum Rejection { case transfer, delete }

    /// „Das gehört nicht rein": als Umbuchung behalten oder verwerfen.
    func reject(_ id: UUID, as rejection: Rejection) {
        guard let index = data.entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = data.entries[index]
        if let proposed = entry.suggestion?.categoryID {
            data.memory.reject(entry.signals, as: proposed)
        }
        switch rejection {
        case .transfer:
            entry.kind = .transfer
            entry.status = .confirmed
            entry.categoryID = BudgetCategory.noneID
            entry.refundOf = nil
            entry.suggestion?.decision = .rejected
            data.entries[index] = entry
        case .delete:
            if let external = entry.externalID { data.ignoredExternalIDs.append(external) }
            data.entries.remove(at: index)
        }
        persist()
    }

    /// Alle Vorschläge annehmen, bei denen die Maschine nicht unsicher war.
    @discardableResult
    func acceptAllConfident() -> Int {
        let ids = data.proposals
            .filter { ($0.suggestion?.band ?? .unsure) != .unsure }
            .map(\.id)
        for id in ids { accept(id) }
        return ids.count
    }

    // MARK: - Import

    /// Liest einen Trade-Republic-Export ein. Wirft, wenn es keiner ist.
    @discardableResult
    func importTradeRepublic(_ text: String) throws -> ImportReport {
        let rows = try TradeRepublicExport.parse(text)
        let outcome = ImportPipeline.run(rows: rows, into: data)
        data = outcome.data
        lastReport = outcome.report
        reportTick += 1
        persist()
        return outcome.report
    }

    func setOwnerName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        data.ownerName = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    func setAutoThreshold(_ value: Double) {
        data.autoThreshold = min(1, max(0.6, value))
        persist()
    }

    func toggleOwnIBAN(_ iban: String) {
        let key = iban.uppercased().replacingOccurrences(of: " ", with: "")
        if let i = data.ownIBANs.firstIndex(of: key) {
            data.ownIBANs.remove(at: i)
        } else {
            data.ownIBANs.append(key)
        }
        persist()
    }

    /// IBANs, an die Überweisungen unter dem Namen des Inhabers gingen — Kandidaten
    /// für „eigenes Konto".
    var candidateOwnIBANs: [(iban: String, name: String)] {
        var seen: Set<String> = []
        var result: [(String, String)] = []
        for entry in data.entries {
            guard let iban = entry.counterpartyIBAN, let merchant = entry.merchant,
                  entry.importType?.hasPrefix("TRANSFER") == true,
                  seen.insert(iban).inserted else { continue }
            if let owner = data.ownerName {
                let wanted = MerchantKey.tokens(owner)
                let found = Set(MerchantKey.tokens(merchant))
                guard !wanted.isEmpty, wanted.allSatisfy(found.contains) else { continue }
            }
            result.append((iban, merchant))
        }
        return result
    }

    // MARK: - Kategorien

    @discardableResult
    func addCategory(
        name: String, symbol: String, tint: CategoryTint, direction: Direction
    ) -> BudgetCategory {
        let category = BudgetCategory(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: symbol.isEmpty ? "•" : symbol,
            tint: tint,
            direction: direction,
            sortIndex: (data.categories.map(\.sortIndex).max() ?? -1) + 1)
        data.categories.append(category)
        persist()
        return category
    }

    func updateCategory(_ category: BudgetCategory) {
        guard let index = data.categories.firstIndex(where: { $0.id == category.id })
        else { return }

        var updated = category
        updated.name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.symbol.isEmpty { updated.symbol = "•" }
        data.categories[index] = updated

        // Wird die Richtung gedreht, ziehen die Buchungen mit. Alles andere würde die
        // Kategorie aus ihrem eigenen Ring werfen und die Beträge unauffindbar machen.
        for position in data.entries.indices where data.entries[position].categoryID == updated.id {
            data.entries[position].direction = updated.direction
        }
        persist()
    }

    /// Löschen nimmt Buchungen von Hand mit. Importierte Buchungen wandern stattdessen
    /// in den Posteingang: Ihr Geld ist real, es braucht nur eine neue Kategorie.
    func deleteCategory(_ id: UUID) {
        data.categories.removeAll { $0.id == id }
        var kept: [Entry] = []
        for var entry in data.entries {
            guard entry.categoryID == id else { kept.append(entry); continue }
            guard entry.source == .tradeRepublic else { continue }
            entry.status = .proposed
            entry.suggestion = nil
            if let fallback = data.categories(for: entry.direction).first {
                entry.categoryID = fallback.id
                entry.suggestion = Suggestion(categoryID: fallback.id, confidence: 0,
                                              evidence: [Evidence(kind: .lastUsed, text: "Kategorie gelöscht", strength: 0)])
            } else {
                entry.categoryID = BudgetCategory.noneID
            }
            kept.append(entry)
        }
        data.entries = kept
        for (direction, used) in data.lastUsed where used == id {
            data.lastUsed[direction] = nil
        }
        // Eine Zuordnung auf eine gelöschte Kategorie würde stumm ins Leere zeigen.
        data.memory.forget(category: id)
        persist()
    }

    func moveCategories(for direction: Direction, from source: IndexSet, to destination: Int) {
        var ordered = data.categories(for: direction)

        // Von Hand statt über SwiftUIs `move(fromOffsets:toOffset:)` — der Speicher
        // kennt die Oberfläche nicht und soll sie auch nicht importieren müssen.
        let moving = source.sorted().map { ordered[$0] }
        for index in source.sorted(by: >) { ordered.remove(at: index) }
        let offset = source.filter { $0 < destination }.count
        ordered.insert(contentsOf: moving, at: min(max(0, destination - offset), ordered.count))

        // Die Reihenfolgen der Richtungen werden getrennt vergeben, sonst würde das
        // Sortieren der Ausgaben die Einnahmen durcheinanderbringen.
        let others = data.categories.filter { $0.direction != direction }
        for position in ordered.indices { ordered[position].sortIndex = position }
        data.categories = ordered + others
        persist()
    }

    func resetAllData() {
        try? file.delete()
        data = .seeded()
        persist()
    }

    // MARK: - Intern

    private func mark(_ entry: Entry) {
        lastSaved = entry
        saveTick += 1
    }

    private func persist() {
        revision += 1
        do {
            try file.save(data)
        } catch {
            saveErrorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

extension AppStore {
    /// Ein Speicher für die ganze App.
    ///
    /// Die Oberfläche und die Kurzbefehle greifen auf dieselbe Instanz zu. Ein
    /// Kurzbefehl, der im Hintergrund bucht, läuft im selben Prozess wie die Seite im
    /// Vordergrund — zwei getrennte Speicher würden sich gegenseitig überschreiben,
    /// und zwar genau dann, wenn beide dieselbe Datei für sich beanspruchen.
    static let shared = AppStore.loadFromDisk()

    /// Für Previews und den Simulator, ohne die echte Datei anzufassen.
    static var preview: AppStore {
        AppStore(data: SampleData.make(), file: DataFile(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("budget-preview-\(UUID().uuidString).json")))
    }
}
