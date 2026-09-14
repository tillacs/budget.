// QuickLogIntent.swift
// budget. — buchen, ohne die App zu öffnen
//
// Die Gegenbewegung zu LogExpenseIntent: Der Kurzbefehl fragt selbst nach Betrag und
// Kategorie, in zwei Einblendungen über dem, was gerade auf dem Bildschirm ist, und
// sichert die Buchung im Hintergrund. Man bleibt, wo man war.
//
// Nach der Richtung wird bewusst nicht gefragt: Sie steckt in der Kategorie. „Gehalt"
// ist eine Einnahme, „Essen" eine Ausgabe — eine dritte Einblendung, die den Nutzer
// nach etwas fragt, das die App schon weiß, wäre eine Einblendung zu viel.

import AppIntents
import Foundation

struct QuickLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Buchung erfassen"
    static let description = IntentDescription(
        "Fragt nach Betrag und Kategorie und sichert die Buchung, ohne budget. zu öffnen.",
        categoryName: "Erfassen")

    /// Bleibt aus. Das ist der ganze Zweck dieser Aktion.
    static let openAppWhenRun = false

    // Text und keine Zahl: Sowohl `IntentCurrencyAmount` als auch `Double` reichen
    // getippte Nachkommastellen nicht durch — aus „7,77" wird in beiden Fällen 7,
    // unabhängig vom Trennzeichen und von der Lokalisierung der App. Gelesen wird
    // der Betrag deshalb in `MoneyFormat.parse`, wo er auch geprüft werden kann.
    //
    // Optional, damit das Feld im Editor leer bleibt und `requestValue` unten bei
    // jeder Ausführung fragt.
    @Parameter(
        title: "Betrag (€)",
        inputOptions: String.IntentInputOptions(
            keyboardType: .numbersAndPunctuation,
            capitalizationType: .none,
            autocorrect: false,
            smartQuotes: false,
            smartDashes: false))
    var amount: String?

    // Nicht optional: Das System fragt die Kategorie von sich aus ab, bevor
    // `perform` läuft — und zwar mit der Liste aus `CategoryOptions`.
    @Parameter(
        title: "Kategorie",
        requestValueDialog: IntentDialog("Wofür?"),
        optionsProvider: CategoryOptions())
    var category: String

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$amount) € für \(\.$category)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared

        // Ein leeres oder unlesbares Feld gilt als „nicht gesetzt" und wird abgefragt —
        // auch dann, wenn ein bestehender Kurzbefehl dort noch etwas anderes stehen hat.
        let typed = if let amount, let given = QuickLogIntent.normalized(amount), given > 0 {
            amount
        } else {
            try await $amount.requestValue(IntentDialog("Wie viel? (€, optional mit Notiz)"))
        }

        // Betrag und Notiz stecken in derselben Zeile: „12,50 Bäcker".
        let (value, note) = QuickLogIntent.split(typed)
        guard value > 0 else { throw QuickLogError.zeroAmount }

        // Die Kategorie kann zwischen Auswahl und Ausführung gelöscht worden sein —
        // etwa wenn ein Kurzbefehl sie fest verdrahtet hat.
        guard let stored = CategoryOptions.category(for: category) else {
            throw QuickLogError.unknownCategory(category)
        }

        store.add(Entry(
            amount: value, direction: stored.direction, categoryID: stored.id, note: note))

        return .result(dialog: IntentDialog(
            "\(MoneyFormat.amount(value)) für \(stored.name) gesichert."))
    }

    /// Zerlegt die Eingabe in Betrag und Notiz und rundet den Betrag.
    static func split(_ text: String) -> (Decimal, String) {
        guard let parts = MoneyFormat.amountAndNote(text) else { return (0, "") }
        return (rounded(parts.amount), parts.note)
    }

    private static func rounded(_ value: Decimal) -> Decimal {
        var input = abs(value)
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    /// Vom getippten Text auf einen exakten Betrag: Vorzeichen weg, zwei Stellen.
    /// Das Minus steckt in der Kategorie, nicht im getippten Betrag — wer „-12"
    /// eingibt, meint trotzdem 12 €.
    static func normalized(_ text: String) -> Decimal? {
        guard let parsed = MoneyFormat.parse(text) else { return nil }
        var input = abs(parsed)
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }
}

enum QuickLogError: Error, CustomLocalizedStringResourceConvertible {
    case unknownCategory(String)
    case zeroAmount

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unknownCategory(let name):
            return "Die Kategorie \u{201E}\(name)\u{201C} gibt es in budget. nicht mehr."
        case .zeroAmount:
            return "Ohne Betrag lässt sich nichts buchen."
        }
    }
}
