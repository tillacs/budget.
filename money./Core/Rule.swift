import Foundation

nonisolated struct Pattern: Hashable, Codable, Sendable {
    /// Which text the pattern is tested against. `name` is empty on fee rows, so
    /// `description` has to be reachable on its own.
    nonisolated enum Field: String, Codable, Hashable, Sendable, CaseIterable {
        case merchant
        case detail
        case any
    }

    nonisolated enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case substring
        case regex
    }

    var text: String
    var field: Field
    var kind: Kind

    init(_ text: String, field: Field = .any, kind: Kind = .substring) {
        self.text = text
        self.field = field
        self.kind = kind
    }

    /// `nil` when the pattern is usable. Checked when the rule is authored so a broken
    /// regex surfaces in the editor instead of silently matching nothing forever.
    var validationError: String? {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return "The pattern is empty." }
        guard kind == .regex else { return nil }
        do {
            _ = try NSRegularExpression(pattern: text, options: [.caseInsensitive])
            return nil
        } catch {
            return "Not a valid regular expression."
        }
    }

    func matches(_ transaction: Transaction) -> Bool {
        candidates(in: transaction).contains(where: matches(_:))
    }

    private func candidates(in transaction: Transaction) -> [String] {
        switch field {
        case .merchant: return [transaction.merchant]
        case .detail: return [transaction.detail]
        case .any: return [transaction.merchant, transaction.detail]
        }
    }

    private func matches(_ candidate: String) -> Bool {
        guard !candidate.isEmpty else { return false }
        switch kind {
        case .substring:
            return candidate.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        case .regex:
            guard let expression = try? NSRegularExpression(pattern: text, options: [.caseInsensitive])
            else { return false }
            let range = NSRange(candidate.startIndex..., in: candidate)
            return expression.firstMatch(in: candidate, options: [], range: range) != nil
        }
    }
}

nonisolated struct Rule: Identifiable, Hashable, Codable, Sendable {
    nonisolated enum Matcher: Hashable, Codable, Sendable {
        case mcc(String)
        case pattern(Pattern)
    }

    let id: UUID
    var categoryID: BudgetCategory.ID
    var matcher: Matcher
    var createdAt: Date

    init(id: UUID = UUID(), categoryID: BudgetCategory.ID, matcher: Matcher, createdAt: Date = Date()) {
        self.id = id
        self.categoryID = categoryID
        self.matcher = matcher
        self.createdAt = createdAt
    }

    var isPattern: Bool {
        if case .pattern = matcher { return true }
        return false
    }

    /// Longer patterns are treated as more specific, so a rule for "EDEKA IMPLER" beats a
    /// rule for "EDEKA" without the user having to think about ordering.
    var specificity: Int {
        switch matcher {
        case .pattern(let pattern): return pattern.text.count
        case .mcc: return 0
        }
    }
}

/// The rules a single tap in the Inbox could write. The first is the default; the UI shows
/// it and lets the user pick another before committing.
nonisolated enum RuleProposal {
    static func proposals(
        for transaction: Transaction,
        categoryID: BudgetCategory.ID,
        now: Date = Date()
    ) -> [Rule] {
        var matchers: [Rule.Matcher] = []

        if let mcc = transaction.mcc, !mcc.isEmpty {
            matchers.append(.mcc(mcc))
        }

        let text = transaction.matchableText.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            matchers.append(.pattern(Pattern(text, field: .any, kind: .substring)))

            // "EDEKA Muenchen. Impler" also offers plain "EDEKA", which is usually the rule
            // the user actually wants.
            if let stem = MerchantTokenizer.words(in: text).first,
               stem.count >= 3,
               stem.caseInsensitiveCompare(text) != .orderedSame {
                matchers.append(.pattern(Pattern(stem, field: .any, kind: .substring)))
            }
        }

        return matchers.map { Rule(categoryID: categoryID, matcher: $0, createdAt: now) }
    }
}
