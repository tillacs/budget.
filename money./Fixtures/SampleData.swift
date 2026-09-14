// SampleData.swift
// budget. — Zahlen für Previews und den Simulator. Nie in der echten App.

import Foundation

nonisolated enum SampleData {
    static func make(month: YearMonth = .current()) -> AppData {
        let categories = Seed.categories()

        func entry(_ amount: String, _ name: String, _ day: Int, _ note: String = "") -> Entry {
            let category = categories.first { $0.name == name } ?? categories[0]
            return Entry(
                date: CalendarDate(year: month.year, month: month.month, day: day),
                amount: Decimal(string: amount) ?? 0,
                direction: category.direction,
                categoryID: category.id,
                note: note)
        }

        return AppData(
            entries: [
                entry("2450", "Gehalt", 1, "Gehalt"),
                entry("120", "Sonstiges", 9, "Rückzahlung"),
                entry("556", "Wohnen", 1, "Miete"),
                entry("412.50", "Lebensmittel", 3),
                entry("253.90", "Lebensmittel", 12),
                entry("64.20", "Essen", 4, "Mittag"),
                entry("18.40", "Essen", 6),
                entry("132.10", "Essen", 11, "Geburtstag"),
                entry("49.90", "Abos", 2),
                entry("87.30", "Unterwegs", 7, "Bahn"),
                entry("64", "Freizeit", 13, "Konzert"),
            ],
            categories: categories)
    }
}
