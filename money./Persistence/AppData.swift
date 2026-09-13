import Foundation

/// Everything the app owns, in one Codable value. Transactions come from the CSV and are
/// never edited; the other four fields are the user's own decisions.
nonisolated struct AppData: Codable, Sendable {
    var schemaVersion: Int
    var transactions: [Transaction]
    var categories: [BudgetCategory]
    var rules: [Rule]
    var budgets: [BudgetCategory.ID: Decimal]
    /// One-off corrections that did not warrant a rule.
    var overrides: [Transaction.ID: BudgetCategory.ID]
    var sort: BudgetSort

    static let currentSchemaVersion = 1

    init(
        schemaVersion: Int = AppData.currentSchemaVersion,
        transactions: [Transaction] = [],
        categories: [BudgetCategory] = [],
        rules: [Rule] = [],
        budgets: [BudgetCategory.ID: Decimal] = [:],
        overrides: [Transaction.ID: BudgetCategory.ID] = [:],
        sort: BudgetSort = .urgency
    ) {
        self.schemaVersion = schemaVersion
        self.transactions = transactions
        self.categories = categories
        self.rules = rules
        self.budgets = budgets
        self.overrides = overrides
        self.sort = sort
    }

    /// First launch: the default MCC table, so the very first import already sorts itself.
    static func seeded(now: Date = Date()) -> AppData {
        let (categories, rules) = DefaultSetup.make(now: now)
        return AppData(categories: categories, rules: rules)
    }
}
