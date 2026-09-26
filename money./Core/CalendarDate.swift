import Foundation

/// A date with no timezone attached.
///
/// Budget months are the one place a timezone bug would be invisible and expensive: a
/// booking on the 1st at 00:30 CEST is the previous month in UTC. The CSV's `date` column
/// is already the bank's booking date, so it is kept verbatim rather than converted into a
/// `Date` and back.
nonisolated struct CalendarDate: Hashable, Comparable, Codable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    var yearMonth: YearMonth { YearMonth(year: year, month: month) }

    static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

nonisolated extension CalendarDate {
    /// Strict `yyyy-MM-dd`. Anything else is a parse failure, not a best guess.
    init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }
}

nonisolated extension CalendarDate {
    static func today(now: Date = Date(), calendar: Calendar = .current) -> CalendarDate {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return CalendarDate(
            year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    var numberOfDaysInMonth: Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date)
        else { return 30 }
        return range.count
    }
}

nonisolated extension CalendarDate {
    /// Mittag, nicht Mitternacht: Ein Datum, das durch einen Systemkalender und wieder
    /// zurück läuft, soll auch bei einer Zeitumstellung nicht einen Tag verlieren.
    var asDate: Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)
    }

    init(from date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(
            year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1)
    }
}

nonisolated struct YearMonth: Hashable, Comparable, Codable, Sendable {
    let year: Int
    let month: Int

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    func advanced(by months: Int) -> YearMonth {
        let zeroBased = year * 12 + (month - 1) + months
        return YearMonth(year: zeroBased / 12, month: zeroBased % 12 + 1)
    }

    /// Monate von hier bis dort, mit Vorzeichen.
    func distance(to other: YearMonth) -> Int {
        (other.year * 12 + other.month) - (year * 12 + month)
    }
}

nonisolated extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
