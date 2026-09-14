// MerchantKey.swift
// budget. — wer das Geld bekommen hat
//
// Der Händler ist der einzige Anhaltspunkt, an dem sich eine Kategorie wiedererkennen
// lässt: Wer „REWE" einmal auf Lebensmittel gebucht hat, meint beim nächsten Mal
// wieder Lebensmittel. Das ist bewusst eine Zuordnungstabelle, die der Nutzer selbst
// füllt, und kein Klassifikator — der war in Schema 1 und kommt nicht zurück.

import Foundation

nonisolated enum MerchantKey {
    /// Der Schlüssel, unter dem eine Zuordnung abgelegt wird. Großschreibung und
    /// Leerraum sollen keine zwei Einträge aus demselben Händler machen.
    static func normalized(_ merchant: String) -> String? {
        let trimmed = merchant
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?-–—\"'„“"))
        let collapsed = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard collapsed.count >= 2, collapsed.contains(where: \.isLetter) else { return nil }
        return collapsed.uppercased()
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
