// MerchantKey.swift
// budget. — wer das Geld bekommen hat
//
// Der Händler ist der Anhaltspunkt, an dem sich eine Kategorie wiedererkennen lässt:
// Wer „REWE" einmal auf Lebensmittel gebucht hat, meint beim nächsten Mal wieder
// Lebensmittel. Hier wird aus dem, was Trade Republic liefert („EDEKA MUENCHEN. IMPLER",
// „PAYPAL *nutzer", „DM DROGERIE SAGT DANKE"), ein Schlüssel und eine Handvoll Wörter.

import Foundation

nonisolated enum MerchantKey {
    /// Wörter, die nichts über den Händler sagen: Rechtsformen, Höflichkeiten,
    /// Städte, die auf jedem zweiten Beleg stehen.
    static let noise: Set<String> = [
        "GMBH", "AG", "KG", "UG", "LTD", "INC", "CO", "CIE", "SARL", "SE",
        "SAGT", "DANKE", "FIL", "FILIALE", "MKTP", "WWW", "COM", "DE", "EU",
        "SHOP", "STORE", "ONLINE", "THE", "AND", "UND", "VON", "BEI",
        "PAY", "PAYMENTS", "SUBSCR", "BILL", "NULL",
        "MUENCHEN", "MUNCHEN", "MUC", "BERLIN", "HAMBURG", "BAYERN",
    ]

    /// Präfixe der Zahlungsdienstleister vor dem eigentlichen Namen.
    private static let prefixes = ["PAYPAL *", "PAYPAL*", "SP ", "SQ *", "SQ*", "SUMUP *", "SUMUP*", "IZ *", "IZ*", "BKG*", "AMZN "]

    /// Der Name ohne Dienstleister-Präfix und ohne „sagt Danke".
    static func cleaned(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in prefixes where text.uppercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        if let range = text.range(of: "sagt danke", options: .caseInsensitive) {
            text = String(text[..<range.lowerBound])
        }
        return text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// Die Wörter eines Händlers: Buchstabenfolgen ab drei Zeichen, ohne Rauschen,
    /// klein geschrieben. „EDEKA MUENCHEN. IMPLER" und „EDEKA Ebenhausen" treffen sich
    /// bei „edeka".
    static func tokens(_ raw: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for word in words(of: cleaned(raw)) {
            let upper = word.uppercased()
            guard word.count >= 3, !noise.contains(upper), word.allSatisfy(\.isLetter) else { continue }
            let lower = word.lowercased()
            if seen.insert(lower).inserted { result.append(lower) }
        }
        return result
    }

    /// Der Schlüssel, unter dem eine Zuordnung abgelegt wird. Großschreibung, Leerraum,
    /// Filialnummern und Rauschwörter sollen keine zwei Einträge aus demselben Händler
    /// machen — „Tegut Filiale 2880" und „Tegut Filiale 2881" sind ein Händler.
    static func normalized(_ merchant: String) -> String? {
        let clean = cleaned(merchant)
        // Hinter „PAYPAL *" steht ein Nutzername — der ist als Ganzes die Identität,
        // Ziffern eingeschlossen.
        if merchant.uppercased().trimmingCharacters(in: .whitespaces).hasPrefix("PAYPAL") {
            let user = clean.uppercased()
            return user.count >= 2 && user.contains(where: \.isLetter) ? user : nil
        }
        let kept = words(of: clean)
            .map { $0.uppercased() }
            .filter { word in
                // Reine Zahlen und Bestellcodes (drei und mehr Ziffern) raus,
                // Rauschwörter raus — „NUTZER1" bleibt, „BBY8CWC378Z2" nicht.
                word.contains(where: \.isLetter) && !noise.contains(word)
                    && word.filter(\.isNumber).count < 3
            }
        let joined = kept.joined(separator: " ")
        guard joined.count >= 2 else { return nil }
        return joined
    }

    /// Wie der Händler in einer Liste steht: ohne Präfix, und Großbuchstaben-Belege
    /// werden lesbar gemacht („EDEKA MUENCHEN. IMPLER" → „Edeka Muenchen. Impler").
    static func displayName(_ raw: String) -> String {
        let clean = cleaned(raw)
        guard !clean.isEmpty else { return raw }
        let letters = clean.filter(\.isLetter)
        let isShouting = !letters.isEmpty && letters.allSatisfy(\.isUppercase) && letters.count > 3
        guard isShouting else { return clean }
        return clean.split(separator: " ").map { word -> String in
            // Kurze Kürzel (DM, DB, BMW) bleiben groß.
            if word.count <= 3 { return String(word) }
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    private static func words(of text: String) -> [String] {
        text.split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    /// Den Händler aus einem Fließtext raten.
    ///
    /// Gesucht wird ein großgeschriebenes Wort nach „an", „bei", „von" oder „für" —
    /// so schreiben Zahlungsmails es: „Du hast 12,50 € an REWE gesendet". Trifft das
    /// nicht zu, kommt nichts zurück; dann fragt die Aktion eben nach der Kategorie,
    /// statt eine falsche vorzuschlagen.
    static func guess(in text: String) -> String? {
        let pattern = "\\b(?:an|bei|von|für|at|to)\\s+"
            + "([\\p{Lu}][\\p{L}0-9&.\\-]*(?:\\s+[\\p{Lu}][\\p{L}0-9&.\\-]*)?)"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              let found = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[found])
    }
}
