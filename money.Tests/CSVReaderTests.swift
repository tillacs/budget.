import Foundation
import Testing
@testable import money_

struct CSVReaderTests {
    @Test func quotedFieldKeepsDelimitersAndNewlines() throws {
        let rows = try CSVReader.rows(from: "\"a,b\",\"c\nd\",e")
        #expect(rows.count == 1)
        #expect(rows[0].fields == ["a,b", "c\nd", "e"])
    }

    @Test func doubledQuoteBecomesOneQuote() throws {
        let rows = try CSVReader.rows(from: #""he said ""hi""","x""#)
        #expect(rows[0].fields == [#"he said "hi""#, "x"])
    }

    @Test func emptyFieldsSurvive() throws {
        let rows = try CSVReader.rows(from: "\"a\",\"\",\"\",\"d\"")
        #expect(rows[0].fields == ["a", "", "", "d"])
    }

    @Test func crlfAndBlankLinesAreHandled() throws {
        let rows = try CSVReader.rows(from: "a,b\r\n\r\nc,d\r\n")
        #expect(rows.map(\.fields) == [["a", "b"], ["c", "d"]])
    }

    @Test func lineNumbersPointAtTheRecordStart() throws {
        let rows = try CSVReader.rows(from: "a\n\"multi\nline\"\nz")
        #expect(rows.map(\.line) == [1, 2, 4])
    }

    @Test func byteOrderMarkIsStripped() throws {
        let rows = try CSVReader.rows(from: "\u{FEFF}\"datetime\",\"date\"")
        #expect(rows[0].fields == ["datetime", "date"])
    }

    @Test func unterminatedQuoteIsAnError() {
        #expect(throws: CSVReadError.self) {
            try CSVReader.rows(from: "a,\"b\nc")
        }
    }
}
