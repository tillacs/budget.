// LogIntents.swift
// budget. — die zwei Kurzbefehle, um die es in dieser App geht

import AppIntents

/// Öffnet die App direkt im Ziffernblock.
///
/// Bewusst *mit* Öffnen der App statt still im Hintergrund: Der Betrag und die
/// Kategorie sollen in derselben Bewegung fallen wie der Doppeltipp. Ein stiller
/// Kurzbefehl müsste beides vorher abfragen — in der Kurzbefehle-App, mit deren
/// Tastatur, und das ist genau der Umweg, den das hier ersetzt.
struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Ausgabe erfassen"
    static let description = IntentDescription(
        "Öffnet budget. mit dem Ziffernblock für eine neue Ausgabe.",
        categoryName: "Erfassen")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickEntryRouter.shared.request(.expense)
        return .result()
    }
}

struct LogIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Einnahme erfassen"
    static let description = IntentDescription(
        "Öffnet budget. mit dem Ziffernblock für eine neue Einnahme.",
        categoryName: "Erfassen")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickEntryRouter.shared.request(.income)
        return .result()
    }
}

/// Damit beide ohne Zutun in der Kurzbefehle-App stehen — dort holt man sie sich für
/// „Auf Rückseite tippen", für den Sperrbildschirm oder für Siri ab.
struct BudgetAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Ausgabe in \(.applicationName)",
                "Neue Ausgabe in \(.applicationName)",
                "\(.applicationName) Ausgabe erfassen",
            ],
            shortTitle: "Ausgabe",
            systemImageName: "arrow.down.left")

        AppShortcut(
            intent: QuickLogIntent(),
            phrases: [
                "Buchung in \(.applicationName)",
                "In \(.applicationName) erfassen",
                "\(.applicationName) buchen",
            ],
            shortTitle: "Buchen",
            systemImageName: "plus.circle")

        AppShortcut(
            intent: LogIncomeIntent(),
            phrases: [
                "Einnahme in \(.applicationName)",
                "Neue Einnahme in \(.applicationName)",
                "\(.applicationName) Einnahme erfassen",
            ],
            shortTitle: "Einnahme",
            systemImageName: "arrow.up.right")
    }
}
