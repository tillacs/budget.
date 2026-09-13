import Foundation
import Testing
@testable import money_

struct TransactionCSVParserTests {
    // MARK: Real export

    @Test func parsesEveryRowOfTheRealExport() throws {
        let transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        #expect(transactions.count == CSVFixtures.rowCount)
    }

    @Test func feeIsSeparateFromAmount() throws {
        let atm = try transaction(id: "bc82b0be-fa09-4fea-a274-a259124c6e94")
        #expect(atm.amount == Decimal(string: "-53.06")!)
        #expect(atm.fee == Decimal(string: "-1.00")!)
        #expect(atm.netAmount == Decimal(string: "-54.06")!)
        #expect(atm.spend == Decimal(string: "54.06")!)
        #expect(atm.mcc == "6011")
        #expect(atm.originalAmount == Decimal(string: "-999246.70")!)
        #expect(atm.originalCurrency == "IDR")
        #expect(atm.fxRate == Decimal(string: "0.000053")!)
    }

    @Test func descriptionWithCommasSurvivesQuoting() throws {
        let atm = try transaction(id: "bc82b0be-fa09-4fea-a274-a259124c6e94")
        #expect(atm.detail.hasPrefix("UBUDPASAR ADLDPS, 1.018.846,59 IDR"))
    }

    @Test func aFeeOnlyRowHasNoPrincipal() throws {
        let cardFee = try transaction(id: "b3dd87a9-7c92-49f2-8242-defc1fd43740")
        #expect(cardFee.amount == 0)
        #expect(cardFee.fee == Decimal(string: "-5.00")!)
        #expect(cardFee.spend == Decimal(5))
        #expect(cardFee.merchant.isEmpty)
        // Nothing in `name` to categorize on, so the rule engine gets `description`.
        #expect(cardFee.matchableText == "Trade Republic Card")
        #expect(cardFee.mcc == nil)
    }

    @Test func refundIsNegativeSpend() throws {
        let refund = try transaction(id: "019fd691-dcd3-7b6c-ac2d-b9e132e7e50d")
        #expect(refund.amount == Decimal(2))
        #expect(refund.spend == Decimal(-2))
        #expect(refund.mcc == "5812")
    }

    @Test func directionComesFromAmountNotFromType() throws {
        // Named …_INBOUND, but the money leaves the account.
        let directDebit = try transaction(id: "019fcb8a-c696-7cf2-ab11-2ecef4d45c41")
        #expect(directDebit.type == TransactionType(rawValue: "TRANSFER_DIRECT_DEBIT_INBOUND"))
        #expect(directDebit.amount < 0)
        #expect(directDebit.spend > 0)
    }

    @Test func tradingRowsAreDistinguishableFromCash() throws {
        let transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        let trading = transactions.filter { !$0.isCash }
        #expect(trading.count == 2)
        #expect(trading.allSatisfy { $0.account == .trading })
        #expect(transactions.filter(\.isCash).count == 9)
    }

    @Test func unknownEventTypesDoNotBreakTheImport() throws {
        let interest = try transaction(id: "019fbc33-359b-71e8-b5dc-4cd8f8498cad")
        #expect(interest.type == TransactionType(rawValue: "INTEREST_PAYMENT"))
        #expect(interest.merchant.isEmpty)
        #expect(interest.amount == Decimal(string: "1.94")!)
    }

    // MARK: Dates

    @Test func bothFractionalSecondPrecisionsParse() throws {
        let sixDigits = try transaction(id: "019fccaa-5ffe-74ba-abbb-969255669474")
        let threeDigits = try transaction(id: "f04cafb6-b491-46e3-9324-c5c280c37faa")
        #expect(sixDigits.timestamp.timeIntervalSince1970 > 0)
        #expect(threeDigits.timestamp.timeIntervalSince1970 > 0)
    }

    @Test func theBookingMonthComesFromTheDateColumnNotTheTimestamp() throws {
        // 00:30 UTC on 1 September, booked by the bank on 31 August.
        let csv = CSVFixtures.csv(rows: [CSVFixtures.row([
            .datetime: "2026-09-01T00:30:00.000Z",
            .date: "2026-08-31",
        ])])
        let transaction = try #require(try TransactionCSVParser.parse(csv).transactions.first)
        #expect(transaction.month == YearMonth(year: 2026, month: 8))
        #expect(transaction.bookingDate == CalendarDate(year: 2026, month: 8, day: 31))
    }

    // MARK: MCC

    @Test func mccKeepsLeadingZeros() throws {
        let csv = CSVFixtures.csv(rows: [CSVFixtures.row([.mccCode: "0742"])])
        let transaction = try #require(try TransactionCSVParser.parse(csv).transactions.first)
        #expect(transaction.mcc == "0742")
    }

    @Test func emptyMccIsNil() throws {
        let csv = CSVFixtures.csv(rows: [CSVFixtures.row([.mccCode: ""])])
        let transaction = try #require(try TransactionCSVParser.parse(csv).transactions.first)
        #expect(transaction.mcc == nil)
    }

    // MARK: Header failures

    @Test func aMissingRequiredColumnIsNamed() throws {
        let header = CSVFixtures.header.replacingOccurrences(of: #""mcc_code""#, with: #""mcc""#)
        let csv = CSVFixtures.csv(header: header, rows: [CSVFixtures.baseRow])
        #expect(error(for: csv) == .missingColumns(["mcc_code"]))
    }

    @Test func severalMissingColumnsAreAllNamed() throws {
        let header = #""datetime","date","category","type""#
        let csv = CSVFixtures.csv(header: header, rows: [CSVFixtures.baseRow])
        guard case .missingColumns(let names) = try #require(error(for: csv)) else {
            Issue.record("expected missingColumns")
            return
        }
        #expect(Set(names) == ["name", "amount", "fee", "tax", "currency", "description",
                               "transaction_id", "mcc_code"])
    }

    @Test func aRepeatedColumnIsRejected() throws {
        let header = CSVFixtures.header + #","amount""#
        let csv = header + "\n" + String(repeating: "\"\",", count: 23) + "\"\""
        #expect(error(for: csv) == .duplicateColumns(["amount"]))
    }

    @Test func unknownExtraColumnsAreIgnored() throws {
        let header = CSVFixtures.header + #","some_new_column""#
        let row = CSVFixtures.csv(rows: [CSVFixtures.row([.amount: "-1.50"])])
            .split(separator: "\n")[1]
        let transactions = try TransactionCSVParser.parse(header + "\n" + row + ",\"whatever\"").transactions
        #expect(transactions.first?.amount == Decimal(string: "-1.50")!)
    }

    @Test func columnOrderDoesNotMatter() throws {
        let reversed = CSVFixtures.header
            .split(separator: ",")
            .reversed()
            .joined(separator: ",")
        let csv = CSVFixtures.csv(header: reversed, rows: [CSVFixtures.row([.amount: "-4.20"])])
        let transaction = try #require(try TransactionCSVParser.parse(csv).transactions.first)
        #expect(transaction.amount == Decimal(string: "-4.20")!)
        #expect(transaction.mcc == "5411")
    }

    @Test func emptyFileIsRejected() {
        #expect(error(for: "") == .emptyFile)
    }

    // MARK: One bad row must never cost the whole file

    @Test func oneUnreadableRowDoesNotStopTheOthers() throws {
        let csv = CSVFixtures.csv(rows: [
            CSVFixtures.row([.transactionID: "good-1", .amount: "-10.00"]),
            CSVFixtures.row([.transactionID: "bad", .amount: "-12,57"]),
            CSVFixtures.row([.transactionID: "good-2", .amount: "-20.00"]),
        ])
        let result = try TransactionCSVParser.parse(csv)

        #expect(result.transactions.map(\.id) == ["good-1", "good-2"])
        #expect(result.failures.count == 1)
        #expect(result.failures[0].line == 3)
        #expect(result.failures[0].reason.contains("amount"))
    }

    @Test func missingTrailingColumnsAreTreatedAsEmptyFields() throws {
        // Row stops after transaction_id: the four trailing columns are simply absent.
        let csv = CSVFixtures.header + "\n"
            + #""2026-08-04T12:00:00Z","2026-08-04","DEFAULT","CASH","CARD_TRANSACTION","","Kiosk","","","","-4.20","","","EUR","","","","Kiosk","short-row""#
        let result = try TransactionCSVParser.parse(csv)

        #expect(result.failures.isEmpty)
        let transaction = try #require(result.transactions.first)
        #expect(transaction.amount == Decimal(string: "-4.20")!)
        #expect(transaction.merchant == "Kiosk")
        #expect(transaction.mcc == nil)
    }

    @Test func aRowTooShortToCarryAnIdIsSkippedNotGuessed() throws {
        let csv = CSVFixtures.header + "\n" + #""2026-08-04","2026-08-04""#
        let result = try TransactionCSVParser.parse(csv)
        #expect(result.transactions.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].line == 2)
    }

    @Test func anEmptyAmountIsZeroNotAFailure() throws {
        let csv = CSVFixtures.csv(rows: [CSVFixtures.row([.amount: ""])])
        let result = try TransactionCSVParser.parse(csv)
        #expect(result.failures.isEmpty)
        // An empty field cannot be hiding a number, so nothing is lost by reading it as zero.
        #expect(result.transactions.first?.amount == 0)
    }

    @Test func aMissingDateFallsBackToTheTimestamp() throws {
        let csv = CSVFixtures.csv(rows: [CSVFixtures.row([
            .date: "", .datetime: "2026-08-31T23:30:00.000Z",
        ])])
        let transaction = try #require(try TransactionCSVParser.parse(csv).transactions.first)
        #expect(transaction.bookingDate == CalendarDate(year: 2026, month: 8, day: 31))
    }

    @Test func aMissingTimestampFallsBackToTheDate() throws {
        let csv = CSVFixtures.csv(rows: [CSVFixtures.row([.datetime: "", .date: "2026-08-04"])])
        let transaction = try #require(try TransactionCSVParser.parse(csv).transactions.first)
        #expect(transaction.bookingDate == CalendarDate(year: 2026, month: 8, day: 4))
        #expect(transaction.timestamp.timeIntervalSince1970 > 0)
    }

    @Test func aRowWithNoUsableDateIsSkippedAndReported() throws {
        let csv = CSVFixtures.csv(rows: [
            CSVFixtures.row([.transactionID: "ok"]),
            CSVFixtures.row([.transactionID: "nodate", .date: "", .datetime: ""]),
        ])
        let result = try TransactionCSVParser.parse(csv)
        #expect(result.transactions.map(\.id) == ["ok"])
        #expect(result.failures.first?.reason.contains("Datum") == true)
    }

    @Test func aRowWithoutAnIdIsSkippedBecauseItCannotBeDeduplicated() throws {
        let csv = CSVFixtures.csv(rows: [CSVFixtures.row([.transactionID: ""])])
        let result = try TransactionCSVParser.parse(csv)
        #expect(result.transactions.isEmpty)
        #expect(result.failures.first?.reason.contains("transaction_id") == true)
    }

    @Test func emptyCurrencyAndTypeDoNotStopARow() throws {
        let csv = CSVFixtures.csv(rows: [CSVFixtures.row([.currency: "", .type: ""])])
        let transaction = try #require(try TransactionCSVParser.parse(csv).transactions.first)
        #expect(transaction.currency == "EUR")
        #expect(transaction.type == TransactionType(rawValue: "UNKNOWN"))
    }

    @Test func aMissingAccountColumnValueIsInferred() throws {
        let cash = CSVFixtures.csv(rows: [CSVFixtures.row([.category: ""])])
        #expect(try TransactionCSVParser.parse(cash).transactions.first?.isCash == true)

        let security = CSVFixtures.csv(rows: [CSVFixtures.row([
            .category: "", .symbol: "US67066G1040", .assetClass: "STOCK",
        ])])
        #expect(try TransactionCSVParser.parse(security).transactions.first?.isCash == false)
    }

    @Test func theRealExportImportsWithNoFailuresAtAll() throws {
        let result = try TransactionCSVParser.parse(CSVFixtures.export)
        #expect(result.isCompletelyClean)
        #expect(result.transactions.count == CSVFixtures.rowCount)
    }

    @Test func anEmptyFeeMeansZeroNotAFailure() throws {
        let csv = CSVFixtures.csv(rows: [CSVFixtures.row([.fee: "", .tax: ""])])
        let transaction = try #require(try TransactionCSVParser.parse(csv).transactions.first)
        #expect(transaction.fee == 0)
        #expect(transaction.tax == 0)
        #expect(transaction.netAmount == transaction.amount)
    }

    // MARK: Helpers

    private func transaction(id: String) throws -> Transaction {
        let transactions = try TransactionCSVParser.parse(CSVFixtures.export).transactions
        return try #require(transactions.first { $0.id == id })
    }

    private func error(for csv: String) -> TransactionCSVError? {
        do {
            _ = try TransactionCSVParser.parse(csv).transactions
            return nil
        } catch let error as TransactionCSVError {
            return error
        } catch {
            return nil
        }
    }
}
