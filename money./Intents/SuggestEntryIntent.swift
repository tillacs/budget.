// SuggestEntryIntent.swift
// budget. — aus einem Text einen Vorschlag machen
//
// Der Anschluss an alles, was iOS von sich aus auslösen kann: der Wallet-Auslöser
// („wenn ich eine Wallet-Karte verwende"), der E-Mail-Auslöser, das Teilen-Menü.
// Die Aktion nimmt Text entgegen, zieht Betrag und Händler heraus, holt die Kategorie
// aus dem Gedächtnis — und fragt dann nach, bevor sie bucht.
//
// Mitteilungen anderer Apps kann sie nicht lesen. Das kann unter iOS keine App:
// Es gibt keine Schnittstelle dafür und keinen Automations-Auslöser. Was der Nutzer
// von Trade Republic als Push bekommt, erreicht diese Aktion nur, wenn die Zahlung
// über Apple Pay lief — dann greift der Wallet-Auslöser.

import AppIntents
import Foundation

struct SuggestEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Buchung vorschlagen"
    static let description = IntentDescription(
        "Liest Betrag und Händler aus einem Text und fragt nach, bevor budget. bucht.",
        categoryName: "Erfassen")

    static let openAppWhenRun = false

    @Parameter(
        title: "Text",
        inputOptions: String.IntentInputOptions(
            capitalizationType: .none, multiline: true,
            autocorrect: false, smartQuotes: false, smartDashes: false))
    var text: String

    /// Wenn der Auslöser den Händler schon kennt, muss er nicht geraten werden.
    @Parameter(title: "Händler")
    var merchant: String?

    /// Beides optional und nur als Rückfalltür: Steht der Betrag nicht im Text oder
    /// ist der Händler unbekannt, wird hier nachgefragt.
    @Parameter(title: "Betrag (€)")
    var amount: String?

    @Parameter(title: "Kategorie", optionsProvider: CategoryOptions())
    var category: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Buchung aus \(\.$text) vorschlagen") {
            \.$merchant
            \.$amount
            \.$category
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared

        let value = try await resolvedAmount()
        guard value > 0 else { throw QuickLogError.zeroAmount }

        let name = merchant ?? MerchantKey.guess(in: text)
        let chosen = try await resolvedCategory(for: name, in: store)

        // Der Vorschlag. Gebucht wird erst nach dem Tippen auf „Hinzufügen" — das ist
        // der ganze Unterschied zwischen einer Automation und einer Bevormundung.
        let question = confirmation(value: value, merchant: name, category: chosen)
        if #available(iOS 18.0, *) {
            try await requestConfirmation(actionName: .add, dialog: IntentDialog(question))
        } else {
            // Vor iOS 18 gibt es nur die abgelöste Form. Sie fragt dasselbe.
            try await requestConfirmation(
                result: .result(dialog: IntentDialog(question)),
                confirmationActionName: .add)
        }

        store.add(
            Entry(amount: value, direction: chosen.direction, categoryID: chosen.id,
                  note: name ?? ""),
            merchant: name)

        return .result(dialog: IntentDialog(
            "\(MoneyFormat.amount(value)) für \(chosen.name) gesichert."))
    }

    // MARK: - Auflösen

    private func resolvedAmount() async throws -> Decimal {
        if let amount, let given = QuickLogIntent.normalized(amount), given > 0 { return given }
        if let found = MoneyFormat.firstAmount(in: text) { return found }
        return QuickLogIntent.normalized(
            try await $amount.requestValue(IntentDialog("Wie viel? (€)"))) ?? 0
    }

    @MainActor
    private func resolvedCategory(
        for merchant: String?, in store: AppStore
    ) async throws -> BudgetCategory {
        if let category, let picked = CategoryOptions.category(for: category) { return picked }
        // Der Kern dieser Aktion: Was einmal bestätigt wurde, wird nicht neu gefragt.
        if let merchant, let remembered = store.rememberedCategory(forMerchant: merchant) {
            return remembered
        }

        let answer = try await $category.requestValue(IntentDialog(prompt(for: merchant)))
        guard let picked = CategoryOptions.category(for: answer) else {
            throw QuickLogError.unknownCategory(answer)
        }
        return picked
    }

    private func prompt(for merchant: String?) -> LocalizedStringResource {
        guard let merchant else { return "Wofür?" }
        return "Wofür ist die Zahlung an \(merchant)?"
    }

    private func confirmation(
        value: Decimal, merchant: String?, category: BudgetCategory
    ) -> LocalizedStringResource {
        let amount = MoneyFormat.amount(value)
        guard let merchant else {
            return "\(amount) als \(category.name) buchen?"
        }
        return "\(amount) bei \(merchant) als \(category.name) buchen?"
    }
}
