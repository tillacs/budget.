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

    /// Die große Zahl. Ab vierstellig sind Cent Rauschen — darunter sind sie die
    /// Hälfte der Aussage, und „42 €" für 42,50 € wäre schlicht falsch.
    static func hero(_ value: Decimal, code: String = "EUR") -> String {
        abs(value) >= 1000 ? rounded(value, code: code) : amount(value, code: code)
    }

    /// Mit Vorzeichen, für die Ringmitte. Das Plus muss dastehen — ohne es liest
    /// sich ein Überschuss wie ein Betrag ohne Aussage.
    static func signed(_ value: Decimal, code: String = "EUR") -> String {
        let magnitude = hero(abs(value), code: code)
        if value > 0 { return "+" + magnitude }
        if value < 0 { return "−" + magnitude }
        return magnitude
    }

    /// Anteil am Ring, wie in der Liste unter der Grafik.
    static func share(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(value < 0.1 ? 1 : 0)))
    }

    /// Einen getippten Betrag lesen — so, wie ihn jemand hinschreibt.
    ///
    /// Nötig, weil der Zahlen-Resolver von App Intents die Nachkommastellen einer
    /// Eingabe wegwirft: Aus „7,77" wird dort 7. Der Betrag kommt deshalb als Text
    /// aus dem Kurzbefehl und wird hier gelesen.
    ///
    /// Komma und Punkt gelten beide, weil die Tastatur beide anbietet:
    ///
    /// - Stehen beide da, trennt das letzte die Nachkommastellen ab. „1.234,56" und
    ///   „1,234.56" sind damit derselbe Betrag.
    /// - Steht nur ein Komma da, ist es das Dezimalkomma. Im Deutschen ist ein Komma
    ///   nie ein Tausendertrennzeichen, also sind „1,005" ein Euro und ein halber Cent.
    /// - Steht nur ein einzelner Punkt da und folgen ihm genau drei Ziffern, ist er der
    ///   Tausenderpunkt: „1.234" sind 1234 Euro und nicht 1,234.
    static func parse(_ text: String) -> Decimal? {
        let kept = text.filter { $0.isASCIIDigit || $0 == "," || $0 == "." }
        guard kept.contains(where: \.isASCIIDigit) else { return nil }

        let separators = kept.enumerated().filter { $0.element == "," || $0.element == "." }
        var splitAt = separators.last?.offset
        let onlyDots = !separators.contains { $0.element == "," }
        if let at = splitAt, onlyDots, separators.count == 1, kept.count - at - 1 == 3 {
            splitAt = nil
        }

        let characters = Array(kept)
        let whole: String
        let fraction: String
        if let at = splitAt {
            whole = String(characters[..<at]).filter(\.isASCIIDigit)
            fraction = String(characters[(at + 1)...]).filter(\.isASCIIDigit)
        } else {
            whole = kept.filter(\.isASCIIDigit)
            fraction = ""
        }

        let digits = whole.isEmpty ? "0" : whole
        let joined = fraction.isEmpty ? digits : "\(digits).\(fraction)"
        // Fest auf POSIX: Die Zeichenkette ist an dieser Stelle normalisiert, das
        // Trennzeichen der Systemsprache hat hier nichts mehr zu suchen.
        return Decimal(string: joined, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Einen getippten Eintrag in Betrag und Notiz zerlegen: „12,50 Bäcker" ist beides.
    ///
    /// So braucht die Schnellerfassung über den Kurzbefehl keine dritte Einblendung für
    /// die Notiz — wer eine will, hängt sie einfach hinten an, wer keine will, merkt
    /// nichts davon.
    static func amountAndNote(_ text: String) -> (amount: Decimal, note: String)? {
        let pattern = "^\\s*[-+]?\\s*(?:€|EUR)?\\s*([0-9][0-9.,]*)\\s*(?:€|EUR)?\\s*(.*)$"
        guard let expression = try? NSRegularExpression(
                  pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                  in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let amount = parse(String(text[numberRange]))
        else { return nil }

        let note = Range(match.range(at: 2), in: text)
            .map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return (amount, note)
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

    /// Mit Jahr, für Buchungen außerhalb des laufenden Monats: „12. März 2026".
    static func dayLong(_ value: CalendarDate) -> String {
        var components = DateComponents()
        components.year = value.year
        components.month = value.month
        components.day = value.day
        guard let date = Calendar(identifier: .gregorian).date(from: components) else {
            return "\(value.day).\(value.month).\(value.year)"
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
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
