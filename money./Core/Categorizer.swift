import Foundation

nonisolated enum CategoryAssignment: Equatable, Sendable {
    /// Matched a rule the user authored (directly or by tapping in the Inbox).
    case rule(categoryID: BudgetCategory.ID, ruleID: Rule.ID)
    /// The user overrode this one booking without writing a rule.
    case manual(categoryID: BudgetCategory.ID)
    /// The classifier was confident enough to apply this without asking.
    case learned(Suggestion)
    /// Inbox. Carries the best guess, if there was one, for pre-selection.
    case unmatched(suggestion: Suggestion?)

    var categoryID: BudgetCategory.ID? {
        switch self {
        case .rule(let categoryID, _): return categoryID
        case .manual(let categoryID): return categoryID
        case .learned(let suggestion): return suggestion.categoryID
        case .unmatched: return nil
        }
    }

    var needsReview: Bool {
        if case .unmatched = self { return true }
        return false
    }
}

/// Resolution order, first match wins:
///
/// 1. a manual override for this exact booking
/// 2. a merchant/description pattern rule — most specific, user-authored
/// 3. an MCC rule
/// 4. the classifier, but only when it clears its confidence bar
/// 5. the Inbox
nonisolated struct Categorizer: Sendable {
    private let patternRules: [Rule]
    private let mccRules: [String: Rule]
    private let overrides: [Transaction.ID: BudgetCategory.ID]
    private let classifier: LearnedClassifier?

    init(
        rules: [Rule],
        overrides: [Transaction.ID: BudgetCategory.ID] = [:],
        classifier: LearnedClassifier? = nil
    ) {
        // Longest pattern first, then newest, so the order never depends on array order.
        self.patternRules = rules
            .filter(\.isPattern)
            .sorted {
                if $0.specificity != $1.specificity { return $0.specificity > $1.specificity }
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }

        var mccRules: [String: Rule] = [:]
        for rule in rules {
            guard case .mcc(let code) = rule.matcher else { continue }
            // Latest rule for a code wins; re-tapping a category should change the answer.
            if let existing = mccRules[code], existing.createdAt > rule.createdAt { continue }
            mccRules[code] = rule
        }
        self.mccRules = mccRules
        self.overrides = overrides
        self.classifier = classifier
    }

    func assignment(for transaction: Transaction) -> CategoryAssignment {
        if let categoryID = overrides[transaction.id] {
            return .manual(categoryID: categoryID)
        }
        if let rule = patternRules.first(where: { rule in
            guard case .pattern(let pattern) = rule.matcher else { return false }
            return pattern.matches(transaction)
        }) {
            return .rule(categoryID: rule.categoryID, ruleID: rule.id)
        }
        if let mcc = transaction.mcc, let rule = mccRules[mcc] {
            return .rule(categoryID: rule.categoryID, ruleID: rule.id)
        }
        if let confident = classifier?.confidentSuggestion(for: transaction) {
            return .learned(confident)
        }
        return .unmatched(suggestion: classifier?.suggestion(for: transaction))
    }

    /// Bookings on the securities account are not spending and never reach a budget.
    func assignments(for transactions: [Transaction]) -> [Transaction.ID: CategoryAssignment] {
        var result: [Transaction.ID: CategoryAssignment] = [:]
        for transaction in transactions where transaction.isCash {
            result[transaction.id] = assignment(for: transaction)
        }
        return result
    }

    /// The training set for the next classifier: everything the user has effectively
    /// confirmed. Learned assignments are excluded on purpose.
    static func trainingExamples(
        transactions: [Transaction],
        rules: [Rule],
        overrides: [Transaction.ID: BudgetCategory.ID]
    ) -> [LabeledTransaction] {
        let ruleOnly = Categorizer(rules: rules, overrides: overrides, classifier: nil)
        return transactions.compactMap { transaction in
            guard transaction.isCash else { return nil }
            switch ruleOnly.assignment(for: transaction) {
            case .rule(let categoryID, _), .manual(let categoryID):
                return LabeledTransaction(transaction, categoryID)
            case .learned, .unmatched:
                return nil
            }
        }
    }
}
