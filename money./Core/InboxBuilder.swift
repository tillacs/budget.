import Foundation

/// Every uncategorized booking from one shop, collapsed into a single piece of work.
///
/// Without this, a month of groceries is fifteen identical Inbox rows. The whole point of
/// the Inbox is that it empties out, and it cannot empty out one booking at a time.
nonisolated struct InboxGroup: Identifiable, Equatable, Sendable {
    let key: String
    /// What to show — the merchant text of the most recent booking in the group.
    let title: String
    let mcc: String?
    /// Newest first.
    let transactions: [Transaction]
    let suggestion: Suggestion?

    var id: String { key }
    var count: Int { transactions.count }
    var total: Decimal { transactions.reduce(0) { $0 + $1.spend } }
    var latest: CalendarDate { transactions.first?.bookingDate ?? CalendarDate(year: 1970, month: 1, day: 1) }
    var earliest: CalendarDate { transactions.last?.bookingDate ?? latest }
    /// The booking a rule is proposed from.
    var representative: Transaction { transactions[0] }
}

nonisolated enum InboxBuilder {
    /// Two bookings belong together when their merchant text reduces to the same words.
    /// "EDEKA Muenchen. Impler" and "EDEKA MUENCHEN IMPLER" are one shop.
    static func groupKey(for transaction: Transaction) -> String {
        let words = MerchantTokenizer.words(in: transaction.matchableText)
        if !words.isEmpty { return words.joined(separator: " ") }

        let fallback = transaction.matchableText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if !fallback.isEmpty { return fallback }
        // Nothing to read at all — keep it separated by MCC rather than lumping every
        // nameless fee row together.
        return "MCC:" + (transaction.mcc ?? "?")
    }

    static func groups(transactions: [Transaction], categorizer: Categorizer) -> [InboxGroup] {
        let assignments = categorizer.assignments(for: transactions)

        var buckets: [String: [Transaction]] = [:]
        var suggestions: [String: Suggestion] = [:]

        for transaction in transactions {
            guard let assignment = assignments[transaction.id], assignment.needsReview else { continue }
            let key = groupKey(for: transaction)
            buckets[key, default: []].append(transaction)
            if case .unmatched(let suggestion) = assignment, let suggestion, suggestions[key] == nil {
                suggestions[key] = suggestion
            }
        }

        return buckets
            .map { key, bookings in
                let sorted = bookings.sorted {
                    $0.timestamp == $1.timestamp ? $0.id > $1.id : $0.timestamp > $1.timestamp
                }
                return InboxGroup(
                    key: key,
                    title: sorted[0].matchableText,
                    mcc: sorted.compactMap(\.mcc).first,
                    transactions: sorted,
                    suggestion: suggestions[key])
            }
            .sorted {
                // Newest work first; ties broken on key so the order never wobbles.
                $0.transactions[0].timestamp == $1.transactions[0].timestamp
                    ? $0.key < $1.key
                    : $0.transactions[0].timestamp > $1.transactions[0].timestamp
            }
    }
}
