import Foundation
import Testing
@testable import money_

/// Der Betrag kommt aus dem Kurzbefehl als Text, weil App Intents die
/// Nachkommastellen einer getippten Zahl verschluckt. Damit ist dieses Lesen die
/// Stelle, an der Geld verloren gehen kann — also die Stelle mit den meisten Tests.
struct MoneyParseTests {
    @Test(arguments: [
        ("7,77", "7.77"),
        ("7.77", "7.77"),
        ("7", "7"),
        ("0,05", "0.05"),
        ("12,5", "12.5"),
        (",99", "0.99"),
        ("1.234,56", "1234.56"),
        ("1,234.56", "1234.56"),
        // Ein einzelner Punkt mit drei Ziffern dahinter ist der Tausenderpunkt.
        ("1.234", "1234"),
        ("2.450", "2450"),
        // Ein Komma dagegen trennt immer die Nachkommastellen ab.
        ("1,005", "1.005"),
        ("1,234", "1.234"),
    ])
    func liestGetippteBeträge(_ input: String, _ expected: String) throws {
        let parsed = try #require(MoneyFormat.parse(input))
        #expect(parsed == Decimal(string: expected))
    }

    @Test func währungszeichenUndLeerraumStörenNicht() {
        #expect(MoneyFormat.parse(" 7,77 € ") == Decimal(string: "7.77"))
        #expect(MoneyFormat.parse("EUR 12") == Decimal(12))
    }

    @Test func ohneZifferKeinBetrag() {
        #expect(MoneyFormat.parse("") == nil)
        #expect(MoneyFormat.parse("abc") == nil)
        #expect(MoneyFormat.parse(",") == nil)
    }

    /// Das Vorzeichen steckt in der Kategorie, nie im Betrag.
    @Test func vorzeichenWirdVerworfen() {
        #expect(QuickLogIntent.normalized("-12,50") == Decimal(string: "12.5"))
    }

    @Test func rundetAufZweiStellen() {
        #expect(QuickLogIntent.normalized("1,005") == Decimal(string: "1.01"))
        #expect(QuickLogIntent.normalized("1,004") == Decimal(string: "1"))
    }

    @Test func unlesbaresGibtNichtsZurück() {
        #expect(QuickLogIntent.normalized("keine Zahl") == nil)
    }
}
