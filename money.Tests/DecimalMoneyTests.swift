import Foundation
import Testing
@testable import money_

/// The spec's requirement that money is `Decimal` and never `Double`, made into a failing
/// test if anyone ever routes an amount through binary floating point.
struct DecimalMoneyTests {
    @Test func sixDecimalPlacesParseExactly() throws {
        let parsed = try #require(TransactionCSVParser.decimal(from: "-53.060000"))
        #expect(parsed == Decimal(string: "-53.06")!)
        #expect(parsed.description == "-53.06")
    }

    @Test func repeatedAdditionStaysExactWhereDoubleDrifts() throws {
        let raw = Array(repeating: "0.07", count: 100)

        let decimalTotal = try raw.reduce(Decimal(0)) {
            $0 + (try #require(TransactionCSVParser.decimal(from: $1)))
        }
        #expect(decimalTotal == Decimal(7))

        // The reason the app never stores money as Double.
        let doubleTotal = raw.reduce(0.0) { $0 + Double($1)! }
        #expect(doubleTotal != 7.0)
    }

    @Test func multiplicationStaysExactWhereDoubleDrifts() {
        #expect(Decimal(string: "1.1")! * 3 == Decimal(string: "3.3")!)
        #expect(1.1 * 3 != 3.3)
    }

    @Test func transactionTotalsAreExact() throws {
        let csv = CSVFixtures.csv(rows: (0..<3).map { index in
            CSVFixtures.row([.amount: "-0.10", .transactionID: "id-\(index)"])
        })
        let total = try TransactionCSVParser.parse(csv).transactions.reduce(Decimal(0)) { $0 + $1.spend }
        #expect(total == Decimal(string: "0.30")!)
    }

    @Test func aDecimalFloatLiteralIsNotExactMoney() {
        // The trap: this looks like a Decimal but was built from a Double.
        let literal: Decimal = -27.81
        #expect(literal != Decimal(string: "-27.81")!)
        #expect(TransactionCSVParser.decimal(from: "-27.81")! == Decimal(string: "-27.81")!)

        // Whole numbers are safe, which is why the bug hides so well.
        let whole: Decimal = -1200
        #expect(whole == Decimal(string: "-1200")!)
    }

    @Test func garbageIsRejectedRatherThanTruncated() {
        // Decimal(string:) alone would return 12 for "12abc".
        #expect(TransactionCSVParser.decimal(from: "12abc") == nil)
        #expect(TransactionCSVParser.decimal(from: "") == nil)
        #expect(TransactionCSVParser.decimal(from: "-") == nil)
        #expect(TransactionCSVParser.decimal(from: "1.2.3") == nil)
        #expect(TransactionCSVParser.decimal(from: "1,20") == nil)
        #expect(TransactionCSVParser.decimal(from: "-53.060000") != nil)
        #expect(TransactionCSVParser.decimal(from: "0.000053") != nil)
    }
}
