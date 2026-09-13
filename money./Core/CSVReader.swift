import Foundation

nonisolated struct CSVRow: Equatable, Sendable {
    /// 1-based line the record starts on, so errors point at something the user can open.
    let line: Int
    let fields: [String]
}

nonisolated enum CSVReadError: Error, Equatable {
    case unterminatedQuotedField(line: Int)
}

/// RFC 4180 reader. Quoted fields may contain the delimiter, newlines, and doubled quotes.
nonisolated enum CSVReader {
    static func rows(from text: String, delimiter: Character = ",") throws -> [CSVRow] {
        var rows: [CSVRow] = []
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var rowHasContent = false
        var line = 1
        var rowStartLine = 1

        var index = text.startIndex
        if text.hasPrefix("\u{FEFF}") { index = text.index(after: index) }

        func finishRow() {
            fields.append(field)
            rows.append(CSVRow(line: rowStartLine, fields: fields))
            fields = []
            field = ""
            rowHasContent = false
        }

        while index < text.endIndex {
            let character = text[index]

            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    if character.isNewline { line += 1 }
                    field.append(character)
                }
                index = text.index(after: index)
                continue
            }

            if character == "\"" {
                inQuotes = true
                rowHasContent = true
            } else if character == delimiter {
                rowHasContent = true
                fields.append(field)
                field = ""
            } else if character.isNewline {
                line += 1
                // Swift treats CRLF as a single Character, so no pair handling is needed.
                if rowHasContent { finishRow() }
                rowStartLine = line
            } else {
                rowHasContent = true
                field.append(character)
            }
            index = text.index(after: index)
        }

        if inQuotes { throw CSVReadError.unterminatedQuotedField(line: rowStartLine) }
        if rowHasContent { finishRow() }
        return rows
    }
}
