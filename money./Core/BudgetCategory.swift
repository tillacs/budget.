import Foundation

/// The three questions a category can answer. They are deliberately different questions,
/// which is why they get different sections on the home screen rather than different rows.
nonisolated enum CategoryKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// "How much is left this month?"
    case spending
    /// "How much came in?" — no budget.
    case income
    /// "Has it been debited yet?" — rent, phone, subscriptions.
    case fixed
}

nonisolated struct BudgetCategory: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var kind: CategoryKind
    var sortIndex: Int

    init(id: UUID = UUID(), name: String, kind: CategoryKind = .spending, sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sortIndex = sortIndex
    }
}
