import Foundation

/// Every column of the Trade Republic `Transaktionsexport`, addressed by header name.
/// Nothing in this file may ever fall back to a column index.
nonisolated enum CSVColumn: String, CaseIterable, Sendable {
    case datetime
    case date
    case accountType = "account_type"
    case category
    case type
    case assetClass = "asset_class"
    case name
    case symbol
    case shares
    case price
    case amount
    case fee
    case tax
    case currency
    case originalAmount = "original_amount"
    case originalCurrency = "original_currency"
    case fxRate = "fx_rate"
    case description
    case transactionID = "transaction_id"
    case counterpartyName = "counterparty_name"
    case counterpartyIBAN = "counterparty_iban"
    case paymentReference = "payment_reference"
    case mccCode = "mcc_code"

    /// Columns that must exist in the header. A missing column here is a structural problem
    /// with the whole file, unlike a missing *value* in one row, which is survivable.
    static let required: [CSVColumn] = [
        .datetime, .date, .category, .type, .name, .amount, .fee, .tax,
        .currency, .description, .transactionID, .mccCode,
    ]
}

/// Problems with the file as a whole. These still abort the import — guessing a column
/// mapping would mis-book every row.
nonisolated enum TransactionCSVError: Error, Equatable {
    case emptyFile
    case missingColumns([String])
    case duplicateColumns([String])
}

nonisolated extension TransactionCSVError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "Die Datei ist leer."
        case .missingColumns(let names):
            return "Im Export fehlt \(names.count == 1 ? "die Spalte" : "die Spalten") "
                + names.joined(separator: ", ") + "."
        case .duplicateColumns(let names):
            return "Die Kopfzeile enthält \(names.count == 1 ? "die Spalte" : "die Spalten") "
                + names.joined(separator: ", ") + " doppelt."
        }
    }
}

/// A single row that could not be read. The rest of the file still imports.
nonisolated struct RowFailure: Equatable, Sendable {
    let line: Int
    let reason: String
}

nonisolated struct CSVParseResult: Equatable, Sendable {
    let transactions: [Transaction]
    let failures: [RowFailure]

    var isCompletelyClean: Bool { failures.isEmpty }
}

/// Header name → column, resolved once per import.
nonisolated struct ColumnMap {
    private let indices: [CSVColumn: Int]
    let fieldCount: Int

    init(header: [String]) throws {
        var byName: [String: Int] = [:]
        var duplicates: Set<String> = []
        for (index, raw) in header.enumerated() {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            if byName[key] != nil { duplicates.insert(key) } else { byName[key] = index }
        }
        guard duplicates.isEmpty else {
            throw TransactionCSVError.duplicateColumns(duplicates.sorted())
        }

        var indices: [CSVColumn: Int] = [:]
        for column in CSVColumn.allCases {
            if let index = byName[column.rawValue] { indices[column] = index }
        }
        let missing = CSVColumn.required.filter { indices[$0] == nil }
        guard missing.isEmpty else {
            throw TransactionCSVError.missingColumns(missing.map(\.rawValue))
        }

        self.indices = indices
        self.fieldCount = header.count
    }

    /// Rows shorter than the header simply have no value for the trailing columns, which is
    /// treated exactly like an empty field rather than as a broken file.
    func value(_ column: CSVColumn, in row: CSVRow) -> String? {
        guard let index = indices[column], index < row.fields.count else { return nil }
        let trimmed = row.fields[index].trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated enum TransactionCSVParser {
    /// Throws only when the header is unusable. Individual rows that cannot be read are
    /// reported and skipped — one odd row must never cost the user the other two thousand.
    static func parse(_ text: String) throws -> CSVParseResult {
        let rows = try CSVReader.rows(from: text)
        guard let header = rows.first else { throw TransactionCSVError.emptyFile }
        let map = try ColumnMap(header: header.fields)

        var transactions: [Transaction] = []
        var failures: [RowFailure] = []

        for row in rows.dropFirst() {
            do {
                transactions.append(try transaction(from: row, map: map))
            } catch let failure as RowError {
                failures.append(RowFailure(line: row.line, reason: failure.reason))
            } catch {
                failures.append(RowFailure(line: row.line, reason: error.localizedDescription))
            }
        }

        return CSVParseResult(transactions: transactions, failures: failures)
    }

    /// Only the things without which a booking is meaningless.
    private struct RowError: Error {
        let reason: String
    }

    static func transaction(from row: CSVRow, map: ColumnMap) throws -> Transaction {
        // Without an id there is no deduplication key, and re-importing would duplicate the
        // row forever. That is the one thing worth dropping a row over.
        guard let id = map.value(.transactionID, in: row) else {
            throw RowError(reason: "keine transaction_id")
        }

        let rawDate = map.value(.date, in: row)
        let rawTimestamp = map.value(.datetime, in: row)

        // Either date column can stand in for the other.
        guard let bookingDate = calendarDate(from: rawDate)
                ?? calendarDate(from: rawTimestamp.map { String($0.prefix(10)) })
        else {
            throw RowError(reason: rawDate == nil && rawTimestamp == nil
                           ? "kein Datum"
                           : "unlesbares Datum „\(rawDate ?? rawTimestamp ?? "")“")
        }

        let timestamp = rawTimestamp.flatMap(timestamp(from:))
            ?? midnight(of: bookingDate)

        func money(_ column: CSVColumn) throws -> Decimal {
            // An empty field cannot be hiding an amount, so zero loses nothing.
            guard let raw = map.value(column, in: row) else { return 0 }
            guard let value = decimal(from: raw) else {
                throw RowError(reason: "unlesbarer Betrag in \(column.rawValue): „\(raw)“")
            }
            return value
        }

        func optionalMoney(_ column: CSVColumn) -> Decimal? {
            map.value(column, in: row).flatMap(decimal(from:))
        }

        return Transaction(
            id: id,
            timestamp: timestamp,
            bookingDate: bookingDate,
            account: accountCategory(in: row, map: map),
            type: TransactionType(rawValue: map.value(.type, in: row) ?? "UNKNOWN"),
            merchant: map.value(.name, in: row) ?? "",
            detail: map.value(.description, in: row) ?? "",
            amount: try money(.amount),
            fee: try money(.fee),
            tax: try money(.tax),
            currency: map.value(.currency, in: row) ?? "EUR",
            originalAmount: optionalMoney(.originalAmount),
            originalCurrency: map.value(.originalCurrency, in: row),
            fxRate: optionalMoney(.fxRate),
            counterpartyName: map.value(.counterpartyName, in: row),
            counterpartyIBAN: map.value(.counterpartyIBAN, in: row),
            paymentReference: map.value(.paymentReference, in: row),
            mcc: map.value(.mccCode, in: row)
        )
    }

    /// With the discriminator missing, a row that names a security is a securities booking
    /// and everything else is cash. Better than dropping the row or guessing blindly.
    private static func accountCategory(in row: CSVRow, map: ColumnMap) -> AccountCategory {
        if let raw = map.value(.category, in: row) { return AccountCategory(rawValue: raw) }
        let looksLikeSecurities = map.value(.symbol, in: row) != nil
            || map.value(.assetClass, in: row) != nil
            || map.value(.shares, in: row) != nil
        return looksLikeSecurities ? .trading : .cash
    }

    /// `Decimal(string:)` stops at the first bad character and returns the prefix, so
    /// "12abc" would silently become 12. Validate the shape first.
    static func decimal(from raw: String) -> Decimal? {
        var body = Substring(raw)
        if body.first == "-" || body.first == "+" { body = body.dropFirst() }

        var sawDigit = false
        var sawSeparator = false
        for character in body {
            if character.isASCIIDigit {
                sawDigit = true
            } else if character == ".", !sawSeparator {
                sawSeparator = true
            } else {
                return nil
            }
        }
        guard sawDigit else { return nil }
        return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func calendarDate(from raw: String?) -> CalendarDate? {
        raw.flatMap(CalendarDate.init(iso:))
    }

    /// Trade Republic writes 3 or 6 fractional digits; `ISO8601DateFormatter` only accepts
    /// 3, so the fraction is dropped. Sub-second precision has no meaning for a budget.
    static func timestamp(from raw: String) -> Date? {
        guard let dot = raw.firstIndex(of: ".") else { return isoFormatter.date(from: raw) }
        var end = raw.index(after: dot)
        while end < raw.endIndex, raw[end].isASCIIDigit { end = raw.index(after: end) }
        return isoFormatter.date(from: String(raw[..<dot]) + String(raw[end...]))
    }

    private static func midnight(of date: CalendarDate) -> Date {
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private static let isoFormatter = ISO8601DateFormatter()
}
