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
    /// der Vorschlag aus einer Zahlungsmail. Falsch liegen kann die Tabelle nicht
    /// folgenschwer — sie schlägt nur vor, gebucht wird erst nach Bestätigung.
    func learn(_ merchant: String?, as category: UUID) {
        guard let merchant, let key = MerchantKey.normalized(merchant) else { return }
        data.merchantCategories[key] = category
    }

    func rememberedCategory(forMerchant merchant: String) -> BudgetCategory? {
        data.rememberedCategory(forMerchant: merchant)
    }

    func update(_ entry: Entry) {
        guard let index = data.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        data.entries[index] = entry
        data.lastUsed[entry.direction.rawValue] = entry.categoryID
        learn(entry.note, as: entry.categoryID)
        mark(entry)
        persist()
    }

    func deleteEntry(_ id: UUID) {
        data.entries.removeAll { $0.id == id }
        persist()
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

    /// Löschen nimmt die Buchungen der Kategorie mit. Sie ohne Kategorie stehen zu
    /// lassen hieße, Beträge zu behalten, die in keinem Ring mehr auftauchen — genau
    /// die Art von unsichtbarem Rest, den diese App nicht haben soll.
    func deleteCategory(_ id: UUID) {
        data.categories.removeAll { $0.id == id }
        data.entries.removeAll { $0.categoryID == id }
        for (direction, used) in data.lastUsed where used == id {
            data.lastUsed[direction] = nil
        }
        // Eine Zuordnung auf eine gelöschte Kategorie würde stumm ins Leere zeigen.
        data.merchantCategories = data.merchantCategories.filter { $0.value != id }
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

        // Die Reihenfolgen beider Richtungen werden getrennt vergeben, sonst würde das
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
