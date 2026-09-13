import Foundation

nonisolated enum MoneyFormat {
    static func amount(_ value: Decimal, code: String = "EUR") -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(2)))
    }

    /// For the one big number. Cents at 50pt are noise, not information.
    static func rounded(_ value: Decimal, code: String = "EUR") -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(0)))
    }

    /// For text fields: the number alone, no currency symbol, local decimal separator.
    static func plain(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    static func month(_ value: YearMonth) -> String {
        guard let date = firstDay(of: value) else { return "\(value.month)/\(value.year)" }
        return date.formatted(.dateTime.month(.wide).year())
    }

    static func day(_ value: CalendarDate) -> String {
        var components = DateComponents()
        components.year = value.year
        components.month = value.month
        components.day = value.day
        guard let date = Calendar(identifier: .gregorian).date(from: components) else {
            return "\(value.day).\(value.month)."
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private static func firstDay(of value: YearMonth) -> Date? {
        var components = DateComponents()
        components.year = value.year
        components.month = value.month
        components.day = 1
        return Calendar(identifier: .gregorian).date(from: components)
    }
}

nonisolated extension YearMonth {
    static func current(now: Date = Date(), calendar: Calendar = .current) -> YearMonth {
        let components = calendar.dateComponents([.year, .month], from: now)
        return YearMonth(year: components.year ?? 2026, month: components.month ?? 1)
    }
}
