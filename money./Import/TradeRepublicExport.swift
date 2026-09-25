// TradeRepublicExport.swift
// budget. — der Transaktionsexport von Trade Republic
//
// Kontoauszüge → Transaktionsexport → Teilen. 23 Spalten, Dezimalpunkt, ISO-Daten,
// alles in Anführungszeichen. Der Export enthält immer die ganze Historie — genau
// deshalb ist die `transaction_id` der Schlüssel gegen Dopplungen.

import Foundation

nonisolated enum TradeRepublicExport {
    struct Row: Hashable, Sendable {
        let datetime: String
        let date: CalendarDate
        let category: String
        let type: String
        let assetClass: String
        let name: String
        let symbol: String
        /// Bereits in Euro, mit Vorzeichen aus Sicht des Kontos. Leer bei Split und
        /// Steueroptimierung.
        let amount: Decimal?
        let description: String
        let transactionID: String
        let counterpartyName: String
        let counterpartyIBAN: String
        let paymentReference: String
        let mcc: String

        /// Ist das ein Kauf aus einem Sparplan? Steht nur in der Beschreibung.
        var isSavingsPlan: Bool {
            type == "BUY" && description.lowercased().hasPrefix("savings plan")
        }
    }

    enum ParseError: Error, LocalizedError, Equatable {
        case empty
        case notATradeRepublicExport
        case missingColumn(String)

        var errorDescription: String? {
            switch self {
            case .empty: return "Die Datei ist leer."
            case .notATradeRepublicExport:
                return "Das ist kein Transaktionsexport von Trade Republic."
            case .missingColumn(let name): return "Die Spalte \u{201E}\(name)\u{201C} fehlt."
            }
        }
    }

    static let requiredColumns = ["date", "type", "amount", "transaction_id", "description"]

    static func parse(_ text: String) throws -> [Row] {
        let table = CSV.parse(text)
        guard let header = table.first else { throw ParseError.empty }
        let index = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1.lowercased(), $0) })
        guard index["transaction_id"] != nil, index["mcc_code"] != nil || index["type"] != nil
        else { throw ParseError.notATradeRepublicExport }
        for column in requiredColumns where index[column] == nil {
            throw ParseError.missingColumn(column)
        }

        return table.dropFirst().compactMap { fields -> Row? in
            func field(_ name: String) -> String {
                guard let i = index[name], i < fields.count else { return "" }
                return fields[i].trimmingCharacters(in: .whitespaces)
            }
            guard let date = CalendarDate(iso: String(field("date").prefix(10))) else { return nil }
            let id = field("transaction_id")
            guard !id.isEmpty else { return nil }
            return Row(
                datetime: field("datetime"),
                date: date,
                category: field("category"),
                type: field("type"),
                assetClass: field("asset_class"),
                name: field("name"),
                symbol: field("symbol"),
                amount: decimal(field("amount")),
                description: field("description"),
                transactionID: id,
                counterpartyName: field("counterparty_name"),
                counterpartyIBAN: field("counterparty_iban").replacingOccurrences(of: " ", with: ""),
                paymentReference: field("payment_reference"),
                mcc: field("mcc_code"))
        }
    }

    private static func decimal(_ text: String) -> Decimal? {
        guard !text.isEmpty,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        return rounded
    }
}

/// Ein kleiner CSV-Leser nach RFC 4180: Anführungszeichen, verdoppelte
/// Anführungszeichen, Zeilenumbrüche innerhalb eines Feldes, CRLF.
nonisolated enum CSV {
    static func parse(_ text: String, separator: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let c = next() {
            if quoted {
                if c == "\"" {
                    if let peek = next() {
                        if peek == "\"" { field.append("\"") } else { quoted = false; pending = peek }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(c)
                }
                continue
            }
            switch c {
            case "\"":
                quoted = true
            case separator:
                row.append(field); field = ""
            case "\r":
                continue
            // „\r\n" ist in Swift *ein* Zeichen — deshalb nicht auf „\n" prüfen.
            case _ where c.isNewline:
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            default:
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
