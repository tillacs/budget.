// ImportPipeline.swift
// budget. — aus Exportzeilen werden Buchungen, ohne dass etwas doppelt zählt
//
// Die sieben Regeln aus dem Konzept, in der Reihenfolge, in der sie je Zeile
// greifen: bekannte ID überspringen, Buchung von Hand übernehmen, Erstattung
// verknüpfen, Saveback paaren, Umbuchung erkennen, sonst die Maschine fragen.
// Am Ende eine Prüfsumme je Monat gegen den Export selbst.
//
// Arbeitet auf einem `AppData`-Wert und gibt einen neuen zurück — ohne Speicher,
// ohne Oberfläche, damit sich jede Regel einzeln testen lässt.

import Foundation

nonisolated struct ImportReport: Hashable, Sendable {
    var rows = 0
    var alreadyKnown = 0
    var withoutAmount = 0
    var adopted = 0
    var autoBooked = 0
    var proposed = 0
    var transfers = 0
    var refundsLinked = 0
    var savebackPairs = 0
    /// Differenz je Monat: Summe der Buchungen minus Summe der Exportzeilen. Muss null sein.
    var checksum: [YearMonth: Decimal] = [:]
    var newestDate: CalendarDate?

    var mismatchedMonths: [YearMonth] {
        checksum.filter { abs($0.value) > Decimal(string: "0.005")! }.keys.sorted()
    }
    var isBalanced: Bool { mismatchedMonths.isEmpty }
    var imported: Int { adopted + autoBooked + proposed + transfers + refundsLinked }
}

nonisolated struct ImportOutcome: Sendable {
    let data: AppData
    let report: ImportReport
}

nonisolated enum ImportPipeline {
    typealias Row = TradeRepublicExport.Row

    static func run(rows: [Row], into input: AppData, now: Date = Date()) -> ImportOutcome {
        var data = input
        var report = ImportReport(rows: rows.count)
        var known = Set(data.entries.compactMap(\.externalID)).union(data.ignoredExternalIDs)
        var index = Dictionary(uniqueKeysWithValues: data.entries.enumerated().map { ($1.id, $0) })

        // Saveback: Gutschrift und Kauf am selben Tag über denselben Betrag und
        // dieselbe ISIN gehören zusammen. Vorab gesucht, weil die Reihenfolge im
        // Export nicht festliegt.
        let savebackByKey = Dictionary(
            rows.filter { $0.type == "BENEFITS_SAVEBACK" && !$0.symbol.isEmpty }
                .map { (pairKey($0), $0.transactionID) },
            uniquingKeysWith: { first, _ in first })
        var savebackBuys: [String: String] = [:]   // Kauf-ID → Gutschrift-ID
        for row in rows where row.type == "BUY" {
            if let credit = savebackByKey[pairKey(row)] { savebackBuys[row.transactionID] = credit }
        }

        let ordered = rows.sorted { ($0.datetime, $0.transactionID) < ($1.datetime, $1.transactionID) }
        var rowAmounts: [YearMonth: Decimal] = [:]
        var entryAmounts: [YearMonth: Decimal] = [:]
        var history = HistoryIndex(data.entries)

        func append(_ entry: Entry) {
            index[entry.id] = data.entries.count
            data.entries.append(entry)
            history.add(entry)
            entryAmounts[entry.month, default: 0] += entry.signedAmount
        }
        func replace(_ entry: Entry) {
            guard let i = index[entry.id] else { return }
            data.entries[i] = entry
        }

        for row in ordered {
            guard let amount = row.amount, amount != 0 else {
                if !known.contains(row.transactionID) {
                    data.ignoredExternalIDs.append(row.transactionID)
                    known.insert(row.transactionID)
                    report.withoutAmount += 1
                }
                continue
            }
            rowAmounts[row.date.yearMonth, default: 0] += amount
            report.newestDate = max(report.newestDate ?? row.date, row.date)

            if known.contains(row.transactionID) {
                report.alreadyKnown += 1
                if let existing = data.entries.first(where: { $0.externalID == row.transactionID }) {
                    entryAmounts[existing.month, default: 0] += existing.signedAmount
                }
                continue
            }
            known.insert(row.transactionID)

            let shape = classify(row, amount: amount, data: data)
            var draft = Entry(
                date: row.date,
                amount: abs(amount),
                direction: shape.direction,
                categoryID: BudgetCategory.noneID,
                note: "",
                createdAt: now,
                source: .tradeRepublic,
                externalID: row.transactionID,
                merchant: shape.merchant,
                mcc: row.mcc.isEmpty ? nil : row.mcc,
                counterpartyIBAN: row.counterpartyIBAN.isEmpty ? nil : row.counterpartyIBAN,
                isin: row.symbol.isEmpty ? nil : row.symbol,
                importType: shape.importType,
                kind: shape.kind,
                status: .proposed)

            // Regel 6: Umbuchung an sich selbst.
            if shape.isOwnTransfer {
                draft.kind = .transfer
                draft.status = .confirmed
                append(draft)
                report.transfers += 1
                continue
            }

            // Regel 3 (Vorläufiges einlösen): eine Buchung von Hand mit demselben
            // Betrag in denselben Tagen ist dieselbe Buchung.
            if shape.kind == .flow,
               let i = data.entries.firstIndex(where: { candidate in
                   candidate.source == .manual && candidate.externalID == nil
                       && candidate.kind == .flow && candidate.direction == draft.direction
                       && candidate.amount == draft.amount
                       && abs(SuggestionEngine.daysBetween(candidate.date, draft.date)) <= 2
               }) {
                var adopted = data.entries[i]
                adopted.source = .tradeRepublic
                adopted.externalID = row.transactionID
                adopted.merchant = draft.merchant
                adopted.mcc = draft.mcc
                adopted.counterpartyIBAN = draft.counterpartyIBAN
                adopted.isin = draft.isin
                adopted.importType = draft.importType
                adopted.date = draft.date
                data.entries[i] = adopted
                entryAmounts[adopted.month, default: 0] += adopted.signedAmount
                data.memory.confirm(adopted.signals, as: adopted.categoryID, at: now)
                report.adopted += 1
                continue
            }

            // Regel 5: Erstattungen.
            if shape.kind == .refund {
                if let original = refundTarget(for: draft, row: row, in: data) {
                    draft.categoryID = original.categoryID
                    draft.refundOf = original.id
                    // Hängt die Ausgabe noch im Posteingang, wartet die Erstattung mit
                    // und folgt ihr, sobald sie entschieden ist.
                    draft.status = original.status == .proposed ? .proposed : .autoBooked
                    draft.suggestion = Suggestion(
                        categoryID: original.categoryID, confidence: 0.95,
                        evidence: [Evidence(
                            kind: .refund,
                            text: "Erstattung von \(original.title.isEmpty ? MoneyFormat.amount(original.amount) : original.title) vom \(MoneyFormat.day(original.date))",
                            strength: 0.95)])
                    append(draft)
                    report.refundsLinked += 1
                    continue
                }
                if draft.direction == .invest {
                    // Verkauf ohne bekannten Kauf: das Wertpapier kennt seine Kategorie vielleicht.
                    ensure(&data, .invest, "Einzelkauf", "🧾", .sand)
                }
            }

            // Regel 6: Geld von einer Person, das genau zu einer Ausgabe passt, ist
            // vermutlich deren Ausgleich — „du hast bezahlt, er schickt es zurück".
            // Nur ein Vorschlag: gleicher Betrag ist ein Hinweis, kein Beweis.
            if shape.kind == .flow, draft.direction == .income, shape.isPersonal,
               let original = reimbursementTarget(for: draft, in: data) {
                draft.kind = .refund
                draft.direction = .expense
                draft.categoryID = original.categoryID
                draft.refundOf = original.id
                draft.status = .proposed
                // Bewusst unter der Schwelle für „sichere annehmen": Ein gleicher Betrag
                // kann Zufall sein, darüber entscheidet der Nutzer Zeile für Zeile.
                draft.suggestion = Suggestion(
                    categoryID: original.categoryID, confidence: 0.55,
                    alternatives: data.categories(for: .income).prefix(2).map(\.id),
                    evidence: [Evidence(
                        kind: .refund,
                        text: "\(original.amount == draft.amount ? "gleicher" : "fast gleicher") Betrag wie \(original.title.isEmpty ? MoneyFormat.amount(original.amount) : original.title) vom \(MoneyFormat.day(original.date))",
                        strength: 0.55)])
                append(draft)
                report.proposed += 1
                continue
            }

            // Saveback-Kauf: die Kategorie „Saveback" im Depot, nicht „Sparplan".
            if savebackBuys[row.transactionID] != nil {
                draft.importType = "BUY_SAVEBACK"
                ensure(&data, .invest, "Saveback", "🎁", .rose)
            }
            if let prior = SuggestionEngine.typePrior(draft.importType), prior.direction == draft.direction,
               let first = prior.names.first {
                let symbol: String
                switch first {
                case "Kapitalerträge": symbol = "💹"
                case "Saveback": symbol = "🎁"
                case "Sparplan": symbol = "📈"
                default: symbol = "🧾"
                }
                ensure(&data, draft.direction, first, symbol, first == "Kapitalerträge" ? .mint : (first == "Sparplan" ? .indigo : .sand))
            }

            // Die Maschine.
            let ranking = SuggestionEngine.rank(
                draft, categories: data.categories, memory: data.memory,
                lastUsed: data.lastUsed[draft.direction.rawValue],
                history: history, now: now)
            guard let ranking else {
                // Keine Kategorie in dieser Richtung — kann bei einer alten Datei
                // ohne Investiert-Bereich passieren. Dann wird eine angelegt.
                ensure(&data, draft.direction, draft.direction == .invest ? "Einzelkauf" : "Sonstiges", "🧾", .slate)
                let fallback = data.categories(for: draft.direction)[0]
                draft.categoryID = fallback.id
                draft.suggestion = Suggestion(categoryID: fallback.id, confidence: 0)
                append(draft)
                report.proposed += 1
                continue
            }
            var suggestion = ranking.suggestion
            if shape.kind == .refund {
                suggestion.evidence.insert(
                    Evidence(kind: .refund, text: "Erstattung ohne passende Ausgabe", strength: 0), at: 0)
            }
            draft.categoryID = suggestion.categoryID
            draft.suggestion = suggestion
            let automatic = shape.kind == .flow && ranking.autoEligible
                && suggestion.confidence >= data.autoThreshold
            draft.status = automatic ? .autoBooked : .proposed
            append(draft)
            if automatic { report.autoBooked += 1 } else { report.proposed += 1 }
        }

        // Saveback-Paare verknüpfen.
        for (buyID, creditID) in savebackBuys {
            guard let b = data.entries.firstIndex(where: { $0.externalID == buyID }),
                  let c = data.entries.firstIndex(where: { $0.externalID == creditID }),
                  data.entries[b].pairedWith == nil
            else { continue }
            data.entries[b].pairedWith = data.entries[c].id
            data.entries[c].pairedWith = data.entries[b].id
            report.savebackPairs += 1
        }

        // Prüfsumme.
        for (month, expected) in rowAmounts {
            report.checksum[month] = (entryAmounts[month] ?? 0) - expected
        }
        if let newest = report.newestDate {
            data.lastImport = ImportStamp(date: now, rows: rows.count, newestDate: newest)
        }
        return ImportOutcome(data: data, report: report)
    }

    // MARK: - Einordnen

    struct Shape {
        var direction: Direction
        var kind: EntryKind
        var merchant: String?
        var importType: String
        var isOwnTransfer = false
        /// Geld von oder an eine Person (Überweisung, PayPal-Freunde) — kein Händler.
        var isPersonal = false
    }

    static func classify(_ row: Row, amount: Decimal, data: AppData) -> Shape {
        let inflow = amount > 0
        let counterparty = counterpartyName(of: row)

        switch row.type {
        case "CARD_TRANSACTION", "CARD_TRANSACTION_INTERNATIONAL":
            let merchant = row.name.isEmpty ? row.description : row.name
            return Shape(direction: .expense, kind: inflow ? .refund : .flow,
                         merchant: merchant, importType: row.type)
        case "BUY":
            return Shape(direction: .invest, kind: .flow, merchant: row.name,
                         importType: row.isSavingsPlan ? "BUY_SAVINGS_PLAN" : "BUY")
        case "SELL":
            return Shape(direction: .invest, kind: .refund, merchant: row.name, importType: "SELL")
        case "IPO_SUBSCRIPTION":
            return Shape(direction: .invest, kind: inflow ? .refund : .flow,
                         merchant: row.name, importType: "IPO_SUBSCRIPTION")
        case "INTEREST_PAYMENT", "DIVIDEND", "BENEFITS_SAVEBACK":
            return Shape(direction: .income, kind: .flow,
                         merchant: row.name.isEmpty ? nil : row.name, importType: row.type)
        case "TRANSFER_INBOUND", "TRANSFER_INSTANT_INBOUND":
            var shape = Shape(direction: inflow ? .income : .expense, kind: .flow,
                              merchant: counterparty, importType: row.type)
            shape.isOwnTransfer = isOwn(row, counterparty: counterparty, data: data)
            shape.isPersonal = true
            return shape
        case "TRANSFER_OUTBOUND", "TRANSFER_INSTANT_OUTBOUND":
            var shape = Shape(direction: inflow ? .income : .expense, kind: .flow,
                              merchant: counterparty, importType: row.type)
            shape.isOwnTransfer = isOwn(row, counterparty: counterparty, data: data)
            return shape
        case "TRANSFER_DIRECT_DEBIT_INBOUND":
            return Shape(direction: inflow ? .income : .expense, kind: .flow,
                         merchant: counterparty, importType: row.type)
        default:
            let merchant = row.name.isEmpty ? (counterparty ?? row.description) : row.name
            return Shape(direction: inflow ? .income : .expense, kind: .flow,
                         merchant: merchant, importType: row.type)
        }
    }

    /// Der Name der Gegenseite: aus der Spalte, sonst aus der Beschreibung
    /// („Incoming transfer from NAME (IBAN)").
    static func counterpartyName(of row: Row) -> String? {
        if !row.counterpartyName.isEmpty { return row.counterpartyName }
        let prefixes = ["Incoming transfer from ", "Outgoing transfer for ", "Sepa Direct Debit transfer to "]
        for prefix in prefixes where row.description.hasPrefix(prefix) {
            var rest = String(row.description.dropFirst(prefix.count))
            if let paren = rest.range(of: " (") { rest = String(rest[..<paren.lowerBound]) }
            return rest.isEmpty ? nil : rest
        }
        return row.name.isEmpty ? nil : row.name
    }

    static func isOwn(_ row: Row, counterparty: String?, data: AppData) -> Bool {
        if !row.counterpartyIBAN.isEmpty, data.ownIBANs.contains(row.counterparty_iban_normalized) { return true }
        guard let owner = data.ownerName?.trimmingCharacters(in: .whitespaces), !owner.isEmpty,
              let counterparty else { return false }
        let wanted = MerchantKey.tokens(owner)
        let found = Set(MerchantKey.tokens(counterparty))
        return !wanted.isEmpty && wanted.allSatisfy(found.contains)
    }

    /// Die Ausgabe, zu der Geld von einer Person passt: (fast) derselbe Betrag,
    /// innerhalb von 30 Tagen davor, noch ohne Ausgleich. Exakt schlägt ungefähr,
    /// dann gewinnt die jüngste.
    static func reimbursementTarget(for inbound: Entry, in data: AppData) -> Entry? {
        let taken = Set(data.entries.compactMap(\.refundOf))
        let candidates = data.entries.filter { original in
            original.kind == .flow && original.direction == .expense
                && original.amount.roughlyEquals(inbound.amount)
                && original.date <= inbound.date
                && SuggestionEngine.daysBetween(original.date, inbound.date) <= 30
                && !taken.contains(original.id)
        }
        let exact = candidates.filter { $0.amount == inbound.amount }
        return (exact.isEmpty ? candidates : exact)
            .max { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }

    /// Die Ausgabe, die eine Erstattung senkt: gleicher Händler, innerhalb von 90
    /// Tagen davor, Betrag mindestens so groß. Exakter Betrag zuerst, dann die jüngste.
    static func refundTarget(for refund: Entry, row: Row, in data: AppData) -> Entry? {
        let refundTokens = Set(refund.signals.tokens)
        let refundKey = refund.signals.merchantKey
        let candidates = data.entries.filter { original in
            guard original.kind == .flow,
                  original.direction == refund.direction,
                  original.amount + Decimal(string: "0.005")! >= refund.amount,
                  original.date <= refund.date,
                  SuggestionEngine.daysBetween(original.date, refund.date) <= 90
            else { return false }
            if refund.direction == .invest {
                return original.isin != nil && original.isin == refund.isin
            }
            let key = original.signals.merchantKey
            if let key, key == refundKey { return true }
            return !refundTokens.isDisjoint(with: original.signals.tokens)
        }
        let exact = candidates.filter { $0.amount == refund.amount }
        let pool = exact.isEmpty ? (refund.direction == .invest ? [] : candidates) : exact
        return pool.max { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }

    private static func pairKey(_ row: Row) -> String {
        "\(row.date.year)-\(row.date.month)-\(row.date.day)|\(row.symbol)|\(abs(row.amount ?? 0))"
    }

    /// Legt eine Kategorie an, falls es sie in dieser Richtung nicht gibt.
    static func ensure(
        _ data: inout AppData, _ direction: Direction, _ name: String, _ symbol: String, _ tint: CategoryTint
    ) {
        guard !data.categories.contains(where: {
            $0.direction == direction && $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }) else { return }
        data.categories.append(BudgetCategory(
            name: name, symbol: symbol, tint: tint, direction: direction,
            sortIndex: (data.categories.map(\.sortIndex).max() ?? -1) + 1))
    }
}

nonisolated private extension TradeRepublicExport.Row {
    var counterparty_iban_normalized: String { counterpartyIBAN.uppercased() }
}
