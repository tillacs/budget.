import Foundation

nonisolated struct ImportSummary: Equatable, Sendable {
    /// Rows in the file, after removing rows the file itself repeats.
    let parsed: Int
    let added: Int
    /// The bank restated a booking that was already stored. The CSV wins.
    let updated: Int
    let unchanged: Int
    let earliest: CalendarDate?
    let latest: CalendarDate?

    static let empty = ImportSummary(
        parsed: 0, added: 0, updated: 0, unchanged: 0, earliest: nil, latest: nil)
}

/// Merging is keyed on `transaction_id`, so importing the same export twice, or importing a
/// full history over a partial one, can only ever converge on the same set.
nonisolated enum TransactionImporter {
    static func merge(
        existing: [Transaction],
        incoming: [Transaction]
    ) -> (transactions: [Transaction], summary: ImportSummary) {
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var added = 0
        var updated = 0
        var unchanged = 0
        var seenInFile: Set<Transaction.ID> = []
        var earliest: CalendarDate?
        var latest: CalendarDate?

        for transaction in incoming {
            // A row repeated inside one file is one booking, not two.
            guard seenInFile.insert(transaction.id).inserted else { continue }

            if earliest == nil || transaction.bookingDate < earliest! {
                earliest = transaction.bookingDate
            }
            if latest == nil || transaction.bookingDate > latest! {
                latest = transaction.bookingDate
            }

            if let stored = byID[transaction.id] {
                if stored == transaction {
                    unchanged += 1
                } else {
                    updated += 1
                    byID[transaction.id] = transaction
                }
            } else {
                added += 1
                byID[transaction.id] = transaction
            }
        }

        let merged = byID.values.sorted {
            $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
        }

        return (
            merged,
            ImportSummary(
                parsed: seenInFile.count, added: added, updated: updated, unchanged: unchanged,
                earliest: earliest, latest: latest)
        )
    }
}
