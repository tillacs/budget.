// SuggestionEngine.swift
// budget. — der Vorschlag zu einer Buchung
//
// Neun Signale, jedes liefert (Kategorie, Stärke, Begründung). Die Stärken werden je
// Kategorie addiert; die Konfidenz ergibt sich aus der absoluten Stärke des besten
// Stapels und seinem Abstand zum zweitbesten. Zwei Kategorien nah beieinander —
// „Essen" oder „Lebensmittel" beim Bäcker — drücken die Konfidenz, und genau dann
// soll die App fragen.
//
// Keine Wahrscheinlichkeitsrechnung, keine Gewichte, die man nicht erklären kann.
// Jede Zahl hier lässt sich in einem Satz im Posteingang wiedergeben.

import Foundation

nonisolated struct Ranking: Hashable, Sendable {
    let suggestion: Suggestion
    /// Darf die Maschine ohne Rückfrage buchen? Nur, wenn genau dieses Signal schon
    /// mehrfach vom Nutzer bestätigt wurde — nie auf ein Vorurteil hin.
    let autoEligible: Bool
}

/// Buchungen nach Händlerschlüssel, einmal gebaut statt bei jedem Vorschlag neu
/// durchsucht — bei 1.600 Zeilen ist das der Unterschied zwischen Sekunden und nichts.
nonisolated struct HistoryIndex: Sendable {
    private var byKey: [String: [Entry]] = [:]

    init(_ entries: [Entry] = []) {
        for entry in entries { add(entry) }
    }

    mutating func add(_ entry: Entry) {
        guard let key = entry.merchant.flatMap(MerchantKey.normalized) else { return }
        byKey[key, default: []].append(entry)
    }

    func entries(forMerchantKey key: String) -> [Entry] { byKey[key] ?? [] }
}

nonisolated enum SuggestionEngine {
    /// Feste Vorbelegungen je Buchungstyp: Zinsen sind Kapitalerträge, ein Sparplan
    /// ist ein Sparplan. Greift nur, wenn eine Kategorie dieses Namens existiert.
    static func typePrior(_ importType: String?) -> (direction: Direction, names: [String], label: String, strength: Double)? {
        switch importType {
        case "INTEREST_PAYMENT": return (.income, ["Kapitalerträge", "Zinsen"], "Zinsen", 0.95)
        case "DIVIDEND": return (.income, ["Kapitalerträge", "Dividenden"], "Dividende", 0.95)
        case "BENEFITS_SAVEBACK": return (.income, ["Saveback"], "Saveback-Gutschrift", 0.95)
        case "BUY_SAVINGS_PLAN": return (.invest, ["Sparplan"], "Sparplan-Ausführung", 0.90)
        case "BUY_SAVEBACK": return (.invest, ["Saveback"], "mit Saveback angelegt", 0.90)
        case "BUY", "IPO_SUBSCRIPTION": return (.invest, ["Einzelkauf"], "Einzelkauf", 0.85)
        case "SELL": return (.invest, ["Einzelkauf", "Sparplan"], "Verkauf", 0.50)
        default: return nil
        }
    }

    static func rank(
        _ draft: Entry,
        categories: [BudgetCategory],
        memory: MerchantMemory,
        lastUsed: UUID?,
        history: HistoryIndex,
        now: Date = Date()
    ) -> Ranking? {
        let candidates = categories.filter { $0.direction == draft.direction }
        guard !candidates.isEmpty else { return nil }
        let allowed = Set(candidates.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let signals = draft.signals

        var scores: [UUID: Double] = [:]
        var evidence: [UUID: [Evidence]] = [:]
        var autoEligible: Set<UUID> = []

        func add(_ id: UUID, _ strength: Double, _ kind: EvidenceKind, _ text: String) {
            guard allowed.contains(id), strength > 0 else { return }
            scores[id, default: 0] += strength
            evidence[id, default: []].append(Evidence(kind: kind, text: text, strength: strength))
        }
        func name(_ id: UUID) -> String { byID[id]?.name ?? "?" }
        func find(_ names: [String]) -> BudgetCategory? {
            for wanted in names {
                if let hit = candidates.first(where: { $0.name.compare(wanted, options: .caseInsensitive) == .orderedSame }) {
                    return hit
                }
            }
            return nil
        }

        // 1. Händler exakt. Wurde derselbe Händler auf zwei Kategorien bestätigt,
        // zählt nur der Überhang — bei Gleichstand sagt der Händler nichts.
        var merchantKnown = false
        if let key = signals.merchantKey {
            let weights = MerchantMemory.weights(memory.byMerchant[key], now: now)
                .sorted { $0.value > $1.value }
            if let best = weights.first {
                let runnerUp = weights.count > 1 ? weights[1].value : 0
                let n = Int((best.value - runnerUp).rounded())
                if n >= 1 {
                    merchantKnown = true
                    let strength = n >= 3 ? 0.95 : (n == 2 ? 0.88 : 0.80)
                    let total = Int(best.value.rounded())
                    add(best.key, strength, .merchant, "\(MerchantKey.displayName(draft.merchant ?? key)) \(total)× als \(name(best.key)) bestätigt")
                    if n >= 2 && memory.confirmations(merchantKey: key, category: best.key) >= 2 {
                        autoEligible.insert(best.key)
                    }
                }
            }
        }

        // 2. Gegenkonto
        if let iban = signals.iban {
            for (id, weight) in MerchantMemory.weights(memory.byIBAN[iban], now: now) {
                add(id, 0.90, .iban, "dieses Konto \(Int(weight.rounded()))× als \(name(id))")
                if weight >= 2 { autoEligible.insert(id) }
            }
        }

        // 3. Wiederkehrend: gleicher Händler, gleicher Betrag, etwa monatlich
        if let key = signals.merchantKey, draft.amount > 0 {
            let tolerance = draft.amount * Decimal(string: "0.02")!
            let same = history.entries(forMerchantKey: key).filter {
                $0.counts && $0.direction == draft.direction
                    && abs($0.amount - draft.amount) <= tolerance
            }
            let monthly = same.filter { previous in
                let days = daysBetween(previous.date, draft.date)
                return (25...35).contains(days) || (55...65).contains(days) || (85...95).contains(days)
            }
            if let previous = monthly.max(by: { $0.date < $1.date }) {
                add(previous.categoryID, 0.10, .recurring, "wiederkehrend, \(MoneyFormat.amount(draft.amount)) monatlich")
            }
        }

        // 4. Wörter — nur für Händler, die nicht selbst bekannt sind. Sonst würde
        // dieselbe Bestätigung dreimal zählen (Händler, Wort, MCC).
        if !signals.tokens.isEmpty, !merchantKnown {
            var tokenScores: [UUID: Double] = [:]
            var bestToken: [UUID: (token: String, score: Double)] = [:]
            var known = 0
            for token in signals.tokens {
                let weights = MerchantMemory.weights(memory.byToken[token], now: now)
                    .filter { allowed.contains($0.key) }
                let total = weights.values.reduce(0, +)
                guard total > 0 else { continue }
                known += 1
                let certainty = min(1, total / 3)
                for (id, weight) in weights {
                    let score = 0.85 * (weight / total) * certainty
                    tokenScores[id, default: 0] += score
                    if score > (bestToken[id]?.score ?? 0) { bestToken[id] = (token, score) }
                }
            }
            if known > 0 {
                for (id, score) in tokenScores {
                    let token = bestToken[id]?.token ?? signals.tokens[0]
                    add(id, score / Double(known), .token, "\u{201E}\(token)\u{201C} bisher meist \(name(id))")
                }
            }
        }

        // 5. MCC gelernt — ebenfalls nur für unbekannte Händler.
        if let mcc = signals.mcc, !merchantKnown {
            let weights = MerchantMemory.weights(memory.byMCC[mcc], now: now)
            let total = weights.values.reduce(0, +)
            if total > 0 {
                let certainty = min(1, total / 5)
                for (id, weight) in weights {
                    add(id, 0.80 * (weight / total) * certainty, .mccLearned,
                        "\(MCCTable.hint(for: mcc)?.label ?? "MCC \(mcc)") bisher \(Int(weight.rounded()))× \(name(id))")
                }
            }
        }

        // 6. MCC-Vorbelegung
        if let hint = MCCTable.hint(for: signals.mcc), let match = find(hint.candidates) {
            add(match.id, 0.55, .mccPrior, "Händlercode: \(hint.label)")
        }

        // 7. Buchungstyp: gelernt, sonst Vorbelegung
        if let type = signals.importType {
            let weights = MerchantMemory.weights(memory.byType[type], now: now)
            let total = weights.values.reduce(0, +)
            if total > 0 {
                for (id, weight) in weights {
                    add(id, 0.95 * (weight / total), .type,
                        "\(typePrior(type)?.label ?? type) \(Int(weight.rounded()))× als \(name(id))")
                    if weight >= 1 && weight == total { autoEligible.insert(id) }
                }
            } else if let prior = typePrior(type), prior.direction == draft.direction,
                      let match = find(prior.names) {
                add(match.id, prior.strength, .type, prior.label)
            }
        }

        // 8. Wertpapier
        if let isin = signals.isin {
            let weights = MerchantMemory.weights(memory.byISIN[isin], now: now)
            let total = weights.values.reduce(0, +)
            if total > 0 {
                for (id, weight) in weights {
                    add(id, 0.85 * (weight / total) * min(1, weight / 2), .isin,
                        "\(draft.merchant ?? isin) bisher \(name(id))")
                    if weight >= 1 && weight == total { autoEligible.insert(id) }
                }
            }
        }

        // 9. Zuletzt benutzt
        if let lastUsed, allowed.contains(lastUsed), scores.isEmpty {
            add(lastUsed, 0.25, .lastUsed, "zuletzt \(name(lastUsed))")
        }

        // Rückfall: gar nichts gefunden → erste Kategorie, ohne Konfidenz.
        guard let top = scores.max(by: { $0.value < $1.value }) else {
            let first = candidates.sorted { $0.sortIndex < $1.sortIndex }[0]
            return Ranking(
                suggestion: Suggestion(categoryID: first.id, confidence: 0,
                                       alternatives: candidates.dropFirst().prefix(2).map(\.id)),
                autoEligible: false)
        }

        let ordered = scores.sorted { $0.value > $1.value }
        let second = ordered.count > 1 ? ordered[1].value : 0
        let strengthFactor = min(1, top.value / 0.9)
        let separation = top.value > 0 ? min(1, (top.value - second) / (0.35 * top.value)) : 0
        let confidence = min(0.99, max(0, strengthFactor * separation))

        var alternatives = ordered.dropFirst().prefix(2).map(\.key)
        for category in candidates.sorted(by: { $0.sortIndex < $1.sortIndex })
        where alternatives.count < 2 && category.id != top.key && !alternatives.contains(category.id) {
            alternatives.append(category.id)
        }

        return Ranking(
            suggestion: Suggestion(
                categoryID: top.key,
                confidence: confidence,
                alternatives: alternatives,
                evidence: (evidence[top.key] ?? []).sorted { $0.strength > $1.strength }),
            autoEligible: autoEligible.contains(top.key))
    }

    static func daysBetween(_ from: CalendarDate, _ to: CalendarDate) -> Int {
        guard let a = from.asDate, let b = to.asDate else { return 0 }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }
}
