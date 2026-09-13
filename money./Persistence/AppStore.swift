import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    private(set) var data: AppData

    /// Rebuilt whenever the data changes rather than on every render — training the
    /// classifier is the one thing here that is not free.
    private(set) var categorizer: Categorizer

    var lastImport: ImportSummary?
    /// Rows the last import could not read. Everything else still came in.
    var lastFailures: [RowFailure] = []
    var importErrorMessage: String?
    var isImporting = false

    private let file: DataFile

    init(data: AppData, file: DataFile = .applicationDefault) {
        self.data = data
        self.file = file
        self.categorizer = AppStore.makeCategorizer(from: data)
    }

    static func loadFromDisk(file: DataFile = .applicationDefault) -> AppStore {
        do {
            if let stored = try file.load() { return AppStore(data: stored, file: file) }
        } catch {
            // A corrupt file must not brick the app. The CSV can rebuild everything except
            // the user's own rules and budgets, so start clean rather than crash-looping.
            try? file.delete()
        }
        let store = AppStore(data: .seeded(), file: file)
        store.persist()
        return store
    }

    // MARK: Import

    func importTransactions(from url: URL) async {
        isImporting = true
        importErrorMessage = nil
        lastFailures = []
        defer { isImporting = false }

        do {
            let text = try DataFile.readText(at: url)
            // A full history export is large enough that parsing it on the main actor would
            // be felt.
            let parsed = try await Task.detached(priority: .userInitiated) {
                try TransactionCSVParser.parse(text)
            }.value

            merge(parsed.transactions)
            lastFailures = parsed.failures
        } catch {
            importErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    // MARK: Mutations

    func setSort(_ sort: BudgetSort) {
        data.sort = sort
        persist()
    }

    /// The merge step on its own, without the file. Reading a CSV is one way to get here;
    /// it is not the only way worth testing.
    func merge(_ incoming: [Transaction]) {
        let (merged, summary) = TransactionImporter.merge(
            existing: data.transactions, incoming: incoming)
        data.transactions = merged
        rebuild()
        persist()
        lastImport = summary
    }

    var inboxGroups: [InboxGroup] {
        InboxBuilder.groups(transactions: data.transactions, categorizer: categorizer)
    }

    /// One tap in the Inbox. Writing the rule is the point — it is what stops the same shop
    /// from asking again.
    ///
    /// A rule derived from one booking does not always match every sibling in the group
    /// (their merchant text can differ in punctuation, or one row may carry no MCC). Those
    /// leftovers get a direct assignment, so the group the user just answered really does
    /// disappear rather than half-disappear.
    func categorize(_ group: InboxGroup, as categoryID: BudgetCategory.ID, writing rule: Rule?) {
        if let rule {
            data.rules.append(rule)
            let withRule = Categorizer(rules: data.rules, overrides: data.overrides)
            for transaction in group.transactions
            where withRule.assignment(for: transaction).categoryID != categoryID {
                data.overrides[transaction.id] = categoryID
            }
        } else {
            for transaction in group.transactions {
                data.overrides[transaction.id] = categoryID
            }
        }
        rebuild()
        persist()
    }

    /// A template arrives complete: category, its rules, and a starting budget the user can
    /// change immediately.
    @discardableResult
    func addCategory(from template: CategoryTemplate) -> BudgetCategory {
        let category = addCategory(name: template.name, kind: template.kind)
        data.rules.append(contentsOf: CategoryTemplates.rules(for: template, categoryID: category.id))
        if let budget = template.suggestedBudget { data.budgets[category.id] = budget }
        rebuild()
        persist()
        return category
    }

    func setKind(_ kind: CategoryKind, for id: BudgetCategory.ID) {
        guard let index = data.categories.firstIndex(where: { $0.id == id }) else { return }
        data.categories[index].kind = kind
        persist()
    }

    func renameCategory(_ id: BudgetCategory.ID, to name: String) {
        guard let index = data.categories.firstIndex(where: { $0.id == id }) else { return }
        data.categories[index].name = name.trimmingCharacters(in: .whitespaces)
        persist()
    }

    /// Deleting a category takes its rules and assignments with it, which sends its bookings
    /// back to the Inbox rather than leaving them pointing at something that no longer exists.
    func deleteCategory(_ id: BudgetCategory.ID) {
        data.categories.removeAll { $0.id == id }
        data.rules.removeAll { $0.categoryID == id }
        data.overrides = data.overrides.filter { $0.value != id }
        data.budgets[id] = nil
        rebuild()
        persist()
    }

    func moveCategory(_ id: BudgetCategory.ID, toIndex index: Int) {
        guard let current = data.categories.firstIndex(where: { $0.id == id }) else { return }
        let category = data.categories.remove(at: current)
        data.categories.insert(category, at: min(max(0, index), data.categories.count))
        for position in data.categories.indices { data.categories[position].sortIndex = position }
        persist()
    }

    @discardableResult
    func addCategory(name: String, kind: CategoryKind) -> BudgetCategory {
        let category = BudgetCategory(
            name: name.trimmingCharacters(in: .whitespaces),
            kind: kind,
            sortIndex: (data.categories.map(\.sortIndex).max() ?? -1) + 1)
        data.categories.append(category)
        persist()
        return category
    }

    func deleteRule(_ id: Rule.ID) {
        data.rules.removeAll { $0.id == id }
        rebuild()
        persist()
    }

    func setBudget(_ amount: Decimal, for category: BudgetCategory.ID) {
        if amount > 0 { data.budgets[category] = amount } else { data.budgets[category] = nil }
        persist()
    }

    /// Wipes everything, including rules and budgets, and reseeds the defaults.
    func resetAllData() {
        try? file.delete()
        data = AppData.seeded()
        rebuild()
        persist()
        lastImport = nil
        importErrorMessage = nil
    }

    // MARK: Internals

    private func rebuild() {
        categorizer = AppStore.makeCategorizer(from: data)
    }

    private func persist() {
        do {
            try file.save(data)
        } catch {
            importErrorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private static func makeCategorizer(from data: AppData) -> Categorizer {
        let examples = Categorizer.trainingExamples(
            transactions: data.transactions, rules: data.rules, overrides: data.overrides)
        return Categorizer(
            rules: data.rules,
            overrides: data.overrides,
            classifier: LearnedClassifier(examples: examples))
    }
}

extension AppStore {
    /// Previews and the simulator, without touching the real container.
    static var preview: AppStore {
        let sample = SampleData.bundle
        return AppStore(data: AppData(
            transactions: sample.transactions,
            categories: sample.categories,
            rules: sample.rules,
            budgets: sample.budgets))
    }
}
