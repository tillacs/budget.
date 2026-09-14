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

/// Betrag und Notiz stecken beim Kurzbefehl in derselben Zeile. Was hier schiefgeht,
/// landet als falscher Betrag oder als verlorene Notiz in der Datei.
struct AmountAndNoteTests {
    @Test(arguments: [
        ("12,50", "12.5", ""),
        ("12,50 Bäcker", "12.5", "Bäcker"),
        ("7,77 € Mittag mit Jan", "7.77", "Mittag mit Jan"),
        ("€ 9,99 Netflix", "9.99", "Netflix"),
        ("40 Tanken", "40", "Tanken"),
        ("  3,20   Kaffee  ", "3.2", "Kaffee"),
    ])
    func trenntBetragUndNotiz(_ input: String, _ amount: String, _ note: String) throws {
        let parts = try #require(MoneyFormat.amountAndNote(input))
        #expect(parts.amount == Decimal(string: amount))
        #expect(parts.note == note)
    }

    @Test func ohneBetragKeineZerlegung() {
        #expect(MoneyFormat.amountAndNote("Bäcker") == nil)
        #expect(MoneyFormat.amountAndNote("") == nil)
    }

    @Test func kurzbefehlNimmtBeides() {
        let (value, note) = QuickLogIntent.split("12,50 Bäcker")
        #expect(value == Decimal(string: "12.5"))
        #expect(note == "Bäcker")
    }
}

/// Der Betrag aus einer Zahlungsmail. Geraten wird nur neben einem Währungszeichen —
/// sonst liest sich ein Datum als Betrag.
struct AmountInTextTests {
    @Test func findetDenBetragNebenDerWährung() {
        #expect(MoneyFormat.firstAmount(in: "Du hast 12,50 € an REWE gesendet")
            == Decimal(string: "12.5"))
        #expect(MoneyFormat.firstAmount(in: "Betrag: EUR 1.234,56 abgebucht")
            == Decimal(string: "1234.56"))
        #expect(MoneyFormat.firstAmount(in: "€9.99 Netflix") == Decimal(string: "9.99"))
    }

    /// Der Grund für die Währungs-Regel: Ein Datum ist kein Betrag.
    @Test func hältDatenUndNummernFürKeineBeträge() {
        #expect(MoneyFormat.firstAmount(in: "Bestellung 12345 vom 03.09.") == nil)
        #expect(MoneyFormat.firstAmount(in: "Sendungsnummer 1.234") == nil)
    }
}

struct MerchantKeyTests {
    @Test func erkenntDenHändlerNachEinerPräposition() {
        #expect(MerchantKey.guess(in: "Du hast 12,50 € an REWE gesendet") == "REWE")
        #expect(MerchantKey.guess(in: "Zahlung bei Netflix International") == "Netflix International")
    }

    @Test func rätNichtWennNichtsDasteht() {
        #expect(MerchantKey.guess(in: "12,50 € abgebucht") == nil)
    }

    /// Groß- und Kleinschreibung dürfen nicht zwei Einträge aus einem Händler machen.
    @Test func normalisiertAufEinenSchlüssel() {
        #expect(MerchantKey.normalized(" rewe ") == MerchantKey.normalized("REWE"))
        #expect(MerchantKey.normalized("Netflix.") == "NETFLIX")
        #expect(MerchantKey.normalized("") == nil)
        #expect(MerchantKey.normalized("7") == nil)
    }
}
