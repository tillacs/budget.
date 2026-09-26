// AppStore.swift
// budget. — der einzige veränderliche Zustand der App

import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    private(set) var data: AppData

    /// Steigt bei jeder Änderung. Die Oberfläche hängt ihre Haptik daran, statt an
    /// jeder einzelnen Mutation.
    private(set) var revision = 0

    var saveErrorMessage: String?

    /// Die zuletzt gesicherte Buchung, mit einem Zähler daneben. Die Oberfläche hängt
    /// ihre Bestätigungsanimation daran — der Zähler, damit zweimal derselbe Betrag
    /// auch zweimal animiert.
    private(set) var lastSaved: Entry?
    private(set) var saveTick = 0

    /// Der letzte Import, für die Zusammenfassung nach dem Teilen.
    private(set) var lastReport: ImportReport?
    private(set) var reportTick = 0

    private let file: DataFile

    /// Die Monatsrechnung ist teuer (alle Buchungen, Ausgleiche, Überschüsse) und
    /// wird bei jedem Bildaufbau gebraucht — deshalb je Monat einmal je Änderung.
    @ObservationIgnored private var summaryCache: [YearMonth: MonthSummary] = [:]
    @ObservationIgnored private var proposalsCache: [Entry]?
    @ObservationIgnored private var monthsCache: Set<YearMonth>?
    /// Speichern läuft im Hintergrund; ein Zähler sorgt dafür, dass nur der
    /// jüngste Stand gewinnt, wenn mehrere Änderungen schnell hintereinander kommen.
    @ObservationIgnored private var saveGeneration = 0

    init(data: AppData, file: DataFile = .applicationDefault) {
        self.data = data
        self.file = file
    }

    static func loadFromDisk(file: DataFile = .applicationDefault) -> AppStore {
        do {
            if let stored = try file.load() {
                let store = AppStore(data: stored, file: file)
                // Was die App inzwischen dazugelernt hat, soll auch für alte Vorschläge gelten.
                store.rerankProposals()
                store.repairTransferDirections()
                store.repairInvestmentKinds()
                return store
            }
        } catch {
            // Eine unlesbare Datei darf die App nicht blockieren. Das gilt auch für die
            // alte Import-Datei aus Schema 1: Sie enthält nichts, was sich in Buchungen
            // übersetzen ließe, also wird sie verworfen statt migriert.
            try? file.delete()
        }
        let store = AppStore(data: .seeded(), file: file)
        store.persist()
        return store
    }

    // MARK: - Auswertung

    func summary(for month: YearMonth) -> MonthSummary {
        if let cached = summaryCache[month] { return cached }
        let made = MonthSummary.make(month: month, entries: data.entries, categories: data.categories)
        summaryCache[month] = made
        return made
    }

    func entries(of category: UUID, in month: YearMonth) -> [Entry] {
        data.entries.of(category: category, in: month)
    }

    /// Monate, in denen etwas steht — plus der laufende, damit man immer irgendwo steht.
    func recordedMonths(including month: YearMonth) -> Set<YearMonth> {
        if monthsCache == nil { monthsCache = data.entries.recordedMonths }
        return (monthsCache ?? []).union([month, .current()])
    }

    /// Die Ausgleiche, die an dieser Buchung hängen.
    func refunds(of original: UUID) -> [Entry] {
        data.entries.filter { $0.refundOf == original && $0.status != .proposed }
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }

    /// Was von einer Buchung nach allen Ausgleichen übrig ist.
    func netAmount(of entry: Entry) -> Decimal {
        max(0, entry.amount - refunds(of: entry.id).reduce(0) { $0 + $1.amount })
    }

    var proposals: [Entry] {
        if let cached = proposalsCache { return cached }
        let made = data.proposals
        proposalsCache = made
        return made
    }
    var hasProposals: Bool { !proposals.isEmpty }

    func entry(_ id: UUID?) -> Entry? {
        guard let id else { return nil }
        return data.entries.first { $0.id == id }
    }

    // MARK: - Buchungen

    func add(_ entry: Entry, merchant: String? = nil) {
        data.entries.append(entry)
        data.lastUsed[entry.direction.rawValue] = entry.categoryID
        learn(merchant ?? entry.note, as: entry.categoryID)
        mark(entry)
        persist()
    }

    /// Merkt sich, welche Kategorie zu einem Händler gehört.
    ///
    /// Gelernt wird auch aus der Notiz einer von Hand erfassten Buchung: Wer „REWE" in
    /// die Notiz tippt und Lebensmittel wählt, hat damit dieselbe Aussage getroffen wie
    /// ein Vorschlag. Falsch liegen kann die Tabelle nicht folgenschwer — sie schlägt
    /// nur vor, gebucht wird erst nach Bestätigung.
    func learn(_ merchant: String?, as category: UUID) {
        guard let merchant, let key = MerchantKey.normalized(merchant) else { return }
        data.memory.confirm(
            Signals(merchantKey: key, tokens: MerchantKey.tokens(merchant)), as: category)
    }

    func rememberedCategory(forMerchant merchant: String) -> BudgetCategory? {
        data.rememberedCategory(forMerchant: merchant)
    }

    func update(_ entry: Entry) {
        guard let index = data.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let before = data.entries[index]
        data.entries[index] = entry
        data.lastUsed[entry.direction.rawValue] = entry.categoryID
        if before.categoryID != entry.categoryID, entry.source == .tradeRepublic {
            // Eine Umkategorisierung ist die deutlichste Aussage, die es gibt.
            data.memory.correct(entry.signals, from: before.categoryID, to: entry.categoryID)
        } else {
            learn(entry.merchant ?? entry.note, as: entry.categoryID)
        }
        mark(entry)
        persist()
    }

    func deleteEntry(_ id: UUID) {
        if let entry = data.entries.first(where: { $0.id == id }), let external = entry.externalID {
            data.ignoredExternalIDs.append(external)
        }
        data.entries.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Posteingang

    /// Den Vorschlag annehmen, wie er ist.
    func accept(_ id: UUID) { accept([id]) }

    /// `announce` lässt die Entscheidung in die Insel fliegen und die Übersicht zum
    /// Monat der Buchung springen — sonst weiß man nicht, wohin sie gegangen ist.
    func accept(_ ids: [UUID], announce: Bool = true) {
        var first = true
        for id in ids {
            guard let index = data.entries.firstIndex(where: { $0.id == id }),
                  data.entries[index].status == .proposed else { continue }
            var entry = data.entries[index]
            entry.status = .confirmed
            entry.suggestion?.decision = .accepted
            data.entries[index] = entry
            data.lastUsed[entry.direction.rawValue] = entry.categoryID
            // Ein Ausgleich sagt nichts über die Kategorie der Person — nicht lernen.
            if entry.kind != .transfer, entry.refundOf == nil {
                data.memory.confirm(learnable(entry, fully: first), as: entry.categoryID)
            }
            settleRefunds(of: entry.id, to: entry.categoryID)
            first = false
        }
        if announce, let last = ids.last, let entry = entry(last) { mark(entry) }
        rerankProposals()
        persist()
    }

    /// Eine Entscheidung über eine Gruppe ist *eine* Entscheidung über Wörter, MCC
    /// und Typ — sonst würde ein Händler mit 200 Zeilen die Vorbelegung für alle
    /// anderen Supermärkte allein bestimmen. Der Händler selbst darf voll zählen.
    private func learnable(_ entry: Entry, fully: Bool) -> Signals {
        var signals = entry.signals
        if !fully {
            signals.tokens = []
            signals.mcc = nil
            signals.importType = nil
        }
        return signals
    }

    /// Eine andere Kategorie als vorgeschlagen — für Vorschläge wie für Gebuchtes.
    func correct(_ id: UUID, to category: UUID) { correct([id], to: category) }

    func correct(_ ids: [UUID], to category: UUID, announce: Bool = true) {
        guard let chosen = data.category(category) else { return }
        var first = true
        for id in ids {
            guard let index = data.entries.firstIndex(where: { $0.id == id }) else { continue }
            var entry = data.entries[index]
            // Das echte Vorzeichen darf sich niemals ändern: Eine Kategorie der
            // falschen Seite wird still ignoriert.
            guard entry.compatibleDirections.contains(chosen.direction) else { continue }
            let proposed = entry.suggestion?.categoryID ?? entry.categoryID
            // Eine vorgeschlagene Erstattung, die doch eine Einnahme ist: Verknüpfung
            // lösen, ganz normal buchen.
            if entry.kind == .refund, chosen.direction != entry.direction {
                entry.kind = .flow
                entry.refundOf = nil
            } else if entry.kind == .refund, entry.refundOf != nil, chosen.id != entry.categoryID {
                entry.refundOf = nil
            }
            entry.categoryID = chosen.id
            entry.direction = chosen.direction
            entry.kind = entry.kind == .transfer ? .flow : entry.kind
            entry.status = .confirmed
            entry.suggestion?.decision = proposed == chosen.id ? .accepted : .corrected(chosen.id)
            data.entries[index] = entry
            data.lastUsed[entry.direction.rawValue] = chosen.id
            data.memory.correct(learnable(entry, fully: first), from: proposed, to: chosen.id)
            settleRefunds(of: entry.id, to: chosen.id)
            first = false
        }
        if announce, let last = ids.last, let entry = entry(last) { mark(entry) }
        rerankProposals()
        persist()
    }

    /// Eine eingegangene Buchung als Ausgleich einer Ausgabe verbuchen: Sie senkt
    /// deren Kategorie, statt als Einnahme zu zählen.
    func linkRefund(_ inboundID: UUID, to originalID: UUID) {
        guard let i = data.entries.firstIndex(where: { $0.id == inboundID }),
              let o = data.entries.firstIndex(where: { $0.id == originalID }),
              // Nur Geld, das reinkam, kann eine Ausgabe ausgleichen.
              data.entries[i].isInflow, !data.entries[o].isInflow else { return }
        // Lag die Ausgabe in Neutral, kommt sie zurück — mit ihrer Seite.
        if data.entries[o].kind == .transfer {
            data.entries[o].kind = .flow
            data.entries[o].direction = .expense
            data.entries[o].status = .confirmed
            if data.category(data.entries[o].categoryID) == nil {
                data.entries[o].categoryID = data.categories(for: .expense).first?.id ?? BudgetCategory.noneID
            }
        }
        let original = data.entries[o]
        var entry = data.entries[i]
        entry.kind = .refund
        entry.direction = original.direction
        entry.categoryID = original.categoryID
        entry.refundOf = original.id
        entry.status = .confirmed
        entry.suggestion?.decision = .accepted
        data.entries[i] = entry
        mark(entry)
        persist()
    }

    /// Eine Umbuchung soll doch zählen: zurück in den Posteingang, mit dem echten
    /// Vorzeichen, damit dort die passende Seite zur Wahl steht.
    func restoreFromNeutral(_ id: UUID) {
        guard let i = data.entries.firstIndex(where: { $0.id == id }),
              data.entries[i].kind == .transfer else { return }
        var entry = data.entries[i]
        let inflow = entry.isInflow
        entry.kind = .flow
        entry.direction = inflow ? .income : .expense
        entry.status = .proposed
        entry.categoryID = data.categories(for: entry.direction).first?.id ?? BudgetCategory.noneID
        entry.suggestion = Suggestion(categoryID: entry.categoryID, confidence: 0)
        data.entries[i] = entry
        rerankProposals()
        persist()
    }

    /// Den Ausgleich wieder lösen: Die Buchung wird zur offenen Einnahme.
    func unlinkRefund(_ id: UUID) {
        guard let i = data.entries.firstIndex(where: { $0.id == id }),
              data.entries[i].kind == .refund, data.entries[i].refundOf != nil else { return }
        var entry = data.entries[i]
        entry.kind = .flow
        entry.direction = .income
        entry.refundOf = nil
        entry.status = .proposed
        entry.categoryID = data.categories(for: .income).first?.id ?? BudgetCategory.noneID
        // Die Ablehnung bleibt stehen, sonst würde derselbe Ausgleich gleich wieder
        // vorgeschlagen.
        entry.suggestion = Suggestion(categoryID: entry.categoryID, confidence: 0, decision: .rejected)
        data.entries[i] = entry
        rerankProposals()
        persist()
    }

    /// Kandidaten für einen Ausgleich: zu einer Einnahme alle Ausgaben, zu einer
    /// Ausgabe alle Eingänge — wirklich alle: auch offene, schon einer Kategorie
    /// zugeordnete, in Neutral geparkte oder bereits anderswo als Ausgleich
    /// verbuchte. Was falsch lag, muss sich von hier aus herausholen lassen.
    /// Sortiert: passender Betrag zuerst, dann die zeitlich nächsten.
    func refundCandidates(for entry: Entry) -> [Entry] {
        let pool = data.entries.filter { other in
            guard other.id != entry.id, other.refundOf != entry.id else { return false }
            if entry.isInflow {
                return !other.isInflow && other.kind != .refund
            } else {
                return other.isInflow
            }
        }
        func distance(_ other: Entry) -> Int {
            abs(SuggestionEngine.daysBetween(other.date, entry.date))
        }
        return pool.sorted { a, b in
            let ea = a.amount == entry.amount, eb = b.amount == entry.amount
            if ea != eb { return ea }
            let ra = a.amount.roughlyEquals(entry.amount), rb = b.amount.roughlyEquals(entry.amount)
            if ra != rb { return ra }
            let da = distance(a), db = distance(b)
            if da != db { return da < db }
            return (a.date, a.createdAt) > (b.date, b.createdAt)
        }
    }

    enum Rejection { case transfer, delete }

    /// „Das gehört nicht rein": als Umbuchung behalten oder verwerfen.
    func reject(_ id: UUID, as rejection: Rejection) { reject([id], as: rejection) }

    func reject(_ ids: [UUID], as rejection: Rejection) {
        var first = true
        for id in ids {
            guard let index = data.entries.firstIndex(where: { $0.id == id }) else { continue }
            var entry = data.entries[index]
            if let proposed = entry.suggestion?.categoryID {
                data.memory.reject(learnable(entry, fully: first), as: proposed)
            }
            first = false
            switch rejection {
            case .transfer:
                // Das Vorzeichen folgt dem Geld, nicht der Seite: Ein Ausgleich steht
                // auf der Ausgabenseite, obwohl das Geld reinkam.
                let inflow = entry.isInflow
                entry.kind = .transfer
                entry.direction = inflow ? .income : .expense
                entry.status = .confirmed
                entry.categoryID = BudgetCategory.noneID
                entry.refundOf = nil
                entry.suggestion?.decision = .rejected
                data.entries[index] = entry
            case .delete:
                if let external = entry.externalID { data.ignoredExternalIDs.append(external) }
                data.entries.remove(at: index)
            }
        }
        rerankProposals()
        persist()
    }

    /// Alle Vorschläge annehmen, bei denen die Maschine nicht unsicher war.
    @discardableResult
    func acceptAllConfident() -> Int {
        // Menschen bleiben draußen: Ihre Zwecke sind zu verschieden für einen Sammelklick.
        let ids = data.proposals
            .filter { entry in
                let band = entry.suggestion?.band ?? .unsure
                // Menschen nur, wenn Person und Betrag zweimal bestätigt sind.
                return entry.isPersonal ? band == .sure : band != .unsure
            }
            .map(\.id)
        accept(ids, announce: false)
        return ids.count
    }

    /// Erstattungen, die an dieser Buchung hängen, übernehmen ihre Entscheidung.
    private func settleRefunds(of original: UUID, to category: UUID) {
        for i in data.entries.indices where data.entries[i].refundOf == original {
            data.entries[i].categoryID = category
            if data.entries[i].status == .proposed { data.entries[i].status = .autoBooked }
        }
    }

    /// Das Lernen wirkt sofort: Nach jeder Entscheidung werden die offenen Vorschläge
    /// neu bewertet. Wer EDEKA zweimal bestätigt hat, sieht die restlichen
    /// EDEKA-Zeilen von selbst aus dem Posteingang verschwinden.
    private func rerankProposals() {
        let history = HistoryIndex(data.entries)
        for i in data.entries.indices {
            let draft = data.entries[i]
            guard draft.status == .proposed, draft.kind != .transfer, draft.refundOf == nil,
                  draft.source == .tradeRepublic else { continue }
            // Ein offener Eingang von einer Person, der genau zu einer Ausgabe passt,
            // wird zum Ausgleich-Vorschlag — auch nachträglich, für ältere Importe.
            if draft.kind == .flow, draft.direction == .income,
               draft.importType?.hasPrefix("TRANSFER") == true,
               draft.suggestion?.decision != .rejected,
               data.memory.personAmountRule(draft.signals.personAmount) == nil,
               let original = ImportPipeline.reimbursementTarget(for: draft, in: data) {
                data.entries[i].kind = .refund
                data.entries[i].direction = .expense
                data.entries[i].categoryID = original.categoryID
                data.entries[i].refundOf = original.id
                data.entries[i].suggestion = Suggestion(
                    categoryID: original.categoryID, confidence: 0.55,
                    alternatives: data.categories(for: .income).prefix(2).map(\.id),
                    evidence: [Evidence(
                        kind: .refund,
                        text: "\(original.amount == draft.amount ? "gleicher" : "fast gleicher") Betrag wie \(original.title.isEmpty ? MoneyFormat.amount(original.amount) : original.title) vom \(MoneyFormat.day(original.date))",
                        strength: 0.55)])
                continue
            }
            guard let ranking = SuggestionEngine.rank(
                      draft, categories: data.categories, memory: data.memory,
                      lastUsed: data.lastUsed[draft.direction.rawValue], history: history)
            else { continue }
            var suggestion = ranking.suggestion
            suggestion.decision = draft.suggestion?.decision
            if draft.kind == .refund {
                suggestion.evidence.insert(
                    Evidence(kind: .refund, text: "Erstattung ohne passende Ausgabe", strength: 0), at: 0)
            }
            data.entries[i].categoryID = suggestion.categoryID
            data.entries[i].suggestion = suggestion
            if draft.kind == .flow, ranking.autoEligible, suggestion.confidence >= data.autoThreshold {
                data.entries[i].status = .autoBooked
            }
        }
    }

    // MARK: - Import

    /// Liest einen Trade-Republic-Export ein. Wirft, wenn es keiner ist.
    @discardableResult
    func importTradeRepublic(_ text: String) throws -> ImportReport {
        let rows = try TradeRepublicExport.parse(text)
        let outcome = ImportPipeline.run(rows: rows, into: data)
        data = outcome.data
        lastReport = outcome.report
        reportTick += 1
        persist()
        return outcome.report
    }

    func setOwnerName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        data.ownerName = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    func setAutoThreshold(_ value: Double) {
        data.autoThreshold = min(1, max(0.6, value))
        persist()
    }

    func toggleOwnIBAN(_ iban: String) {
        let key = iban.uppercased().replacingOccurrences(of: " ", with: "")
        if let i = data.ownIBANs.firstIndex(of: key) {
            data.ownIBANs.remove(at: i)
        } else {
            data.ownIBANs.append(key)
        }
        persist()
    }

    /// IBANs, an die Überweisungen unter dem Namen des Inhabers gingen — Kandidaten
    /// für „eigenes Konto".
    var candidateOwnIBANs: [(iban: String, name: String)] {
        var seen: Set<String> = []
        var result: [(String, String)] = []
        for entry in data.entries {
            guard let iban = entry.counterpartyIBAN, let merchant = entry.merchant,
                  entry.importType?.hasPrefix("TRANSFER") == true,
                  seen.insert(iban).inserted else { continue }
            if let owner = data.ownerName {
                let wanted = MerchantKey.tokens(owner)
                let found = Set(MerchantKey.tokens(merchant))
                guard !wanted.isEmpty, wanted.allSatisfy(found.contains) else { continue }
            }
            result.append((iban, merchant))
        }
        return result
    }

    // MARK: - Kategorien

    @discardableResult
    func addCategory(
        name: String, symbol: String, tint: CategoryTint, direction: Direction
    ) -> BudgetCategory {
        let category = BudgetCategory(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: symbol.isEmpty ? "•" : symbol,
            tint: tint,
            direction: direction,
            sortIndex: (data.categories.map(\.sortIndex).max() ?? -1) + 1)
        data.categories.append(category)
        persist()
        return category
    }

    func updateCategory(_ category: BudgetCategory) {
        guard let index = data.categories.firstIndex(where: { $0.id == category.id })
        else { return }

        var updated = category
        updated.name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.symbol.isEmpty { updated.symbol = "•" }
        // Rein und raus sind keine Meinungssache: Mit Buchungen bleibt die Geldrichtung.
        let before = data.categories[index]
        if before.direction.isOutflow != updated.direction.isOutflow,
           data.entries.contains(where: { $0.categoryID == updated.id }) {
            updated.direction = before.direction
        }
        data.categories[index] = updated

        // Wird die Richtung gedreht, ziehen die Buchungen mit. Alles andere würde die
        // Kategorie aus ihrem eigenen Ring werfen und die Beträge unauffindbar machen.
        for position in data.entries.indices where data.entries[position].categoryID == updated.id {
            data.entries[position].direction = updated.direction
        }
        persist()
    }

    /// Wie viele Buchungen an einer Kategorie hängen — auch Vorschläge.
    func entryCount(in category: UUID) -> Int {
        data.entries.filter { $0.categoryID == category }.count
    }

    /// Löschen nimmt nie Buchungen mit. Hängen welche an der Kategorie, wandern sie
    /// alle auf einmal in die Zielkategorie — Richtung inklusive, Status bleibt.
    /// Ohne Ziel wird nur eine leere Kategorie gelöscht.
    @discardableResult
    func deleteCategory(_ id: UUID, movingEntriesTo target: UUID? = nil) -> Bool {
        let affected = data.entries.indices.filter { data.entries[$0].categoryID == id }
        if !affected.isEmpty {
            guard let target, target != id, let destination = data.category(target) else { return false }
            for i in affected {
                data.entries[i].categoryID = destination.id
                if data.entries[i].kind != .transfer {
                    data.entries[i].direction = destination.direction
                }
            }
        }
        data.categories.removeAll { $0.id == id }
        for (direction, used) in data.lastUsed where used == id {
            data.lastUsed[direction] = target
        }
        // Eine Zuordnung auf eine gelöschte Kategorie würde stumm ins Leere zeigen.
        data.memory.forget(category: id)
        persist()
        return true
    }

    func moveCategories(for direction: Direction, from source: IndexSet, to destination: Int) {
        var ordered = data.categories(for: direction)

        // Von Hand statt über SwiftUIs `move(fromOffsets:toOffset:)` — der Speicher
        // kennt die Oberfläche nicht und soll sie auch nicht importieren müssen.
        let moving = source.sorted().map { ordered[$0] }
        for index in source.sorted(by: >) { ordered.remove(at: index) }
        let offset = source.filter { $0 < destination }.count
        ordered.insert(contentsOf: moving, at: min(max(0, destination - offset), ordered.count))

        // Die Reihenfolgen der Richtungen werden getrennt vergeben, sonst würde das
        // Sortieren der Ausgaben die Einnahmen durcheinanderbringen.
        let others = data.categories.filter { $0.direction != direction }
        for position in ordered.indices { ordered[position].sortIndex = position }
        data.categories = ordered + others
        persist()
    }

    /// Alle eingelesenen Buchungen entfernen, Kategorien und Gelerntes behalten.
    /// Der nächste Export bringt sie wieder — dann mit dem, was die App weiß.
    func resetImport() {
        data.entries.removeAll { $0.source == .tradeRepublic }
        data.ignoredExternalIDs = []
        data.lastImport = nil
        persist()
    }

    /// Das Gedächtnis leeren. Buchungen und Kategorien bleiben.
    func forgetLearning() {
        data.memory = MerchantMemory()
        persist()
    }

    func resetAllData() {
        try? file.delete()
        data = .seeded()
        persist()
    }

    // MARK: - Intern

    /// Das echte Vorzeichen nachtragen, wo es noch fehlt, und Umbuchungen, deren
    /// Seite eine frühere Version verdreht hat, zurücksetzen. Läuft einmal beim Start.
    func repairTransferDirections() {
        var changed = false
        for i in data.entries.indices {
            var entry = data.entries[i]
            if entry.inflow == nil, entry.source == .tradeRepublic, let type = entry.importType {
                let known: Bool?
                if type.contains("DIRECT_DEBIT") { known = false }
                else if type.contains("INBOUND") { known = true }
                else if type.contains("OUTBOUND") { known = false }
                else if ["INTEREST_PAYMENT", "DIVIDEND", "BENEFITS_SAVEBACK", "SELL"].contains(type) { known = true }
                else if type.hasPrefix("BUY") { known = false }
                else if type.hasPrefix("CARD") { known = entry.kind == .refund }
                else { known = nil }
                if let known { entry.inflow = known; changed = true }
            }
            if entry.kind == .transfer, let inflow = entry.inflow {
                let wanted: Direction = inflow ? .income : .expense
                if entry.direction != wanted { entry.direction = wanted; changed = true }
            }
            data.entries[i] = entry
        }
        if changed { persist() }
    }

    /// Depot-Käufe nach den aktuellen Regeln nachsortieren: Saveback- und Round-up-
    /// Käufe, die eine frühere Version als Sparplan gebucht hat. Nur, was die
    /// Maschine selbst gebucht hat — was der Nutzer bestätigt hat, bleibt.
    func repairInvestmentKinds() {
        var changed = false
        let credits = data.entries.filter { ($0.importType.map(ImportPipeline.isBenefit) ?? false) && $0.isInflow }
        var takenCredits: Set<UUID> = []
        for i in data.entries.indices {
            let entry = data.entries[i]
            guard entry.source == .tradeRepublic, entry.direction == .invest, entry.kind == .flow,
                  let type = entry.importType, type.hasPrefix("BUY") else { continue }
            var wanted = type
            // Paar: Gutschrift bis fünf Tage davor, gleicher Betrag, gleiche ISIN.
            if let credit = credits.first(where: { c in
                !takenCredits.contains(c.id) && c.amount == entry.amount
                    && c.date <= entry.date && SuggestionEngine.daysBetween(c.date, entry.date) <= 5
                    && (c.isin == nil || c.isin == entry.isin)
            }) {
                takenCredits.insert(credit.id)
                wanted = (credit.importType ?? "").contains("ROUND") ? "BUY_ROUNDUP" : "BUY_SAVEBACK"
                if data.entries[i].pairedWith == nil, let ci = data.entries.firstIndex(where: { $0.id == credit.id }) {
                    data.entries[i].pairedWith = credit.id
                    data.entries[ci].pairedWith = entry.id
                    changed = true
                }
            } else if type == "BUY_SAVINGS_PLAN", !ImportPipeline.isPlanRate(entry.amount) {
                wanted = "BUY_ROUNDUP"
            } else if type == "BUY_SAVEBACK" || type == "BUY_ROUNDUP" {
                // Ohne Gutschrift war das Paar ein Irrtum; krumm bleibt Round-up.
                wanted = ImportPipeline.isPlanRate(entry.amount) ? "BUY_SAVINGS_PLAN" : "BUY_ROUNDUP"
            }
            guard wanted != type else { continue }
            data.entries[i].importType = wanted
            changed = true
            if entry.status != .confirmed, let prior = SuggestionEngine.typePrior(wanted),
               let name = prior.names.first {
                let symbol = name == "Saveback" ? "🎁" : (name == "Round-up" ? "🔄" : "📈")
                let tint: CategoryTint = name == "Saveback" ? .rose : (name == "Round-up" ? .teal : .indigo)
                ImportPipeline.ensure(&data, .invest, name, symbol, tint)
                if let target = data.categories(for: .invest).first(where: { $0.name == name }) {
                    data.entries[i].categoryID = target.id
                    data.entries[i].suggestion = Suggestion(
                        categoryID: target.id, confidence: 0.9,
                        evidence: [Evidence(kind: .type, text: prior.label, strength: prior.strength)])
                }
            }
        }
        if changed { persist() }
    }

    private func mark(_ entry: Entry) {
        lastSaved = entry
        saveTick += 1
    }

    private func persist() {
        revision += 1
        summaryCache = [:]
        proposalsCache = nil
        monthsCache = nil
        // Im Hintergrund schreiben: Die Datei ist bei 1.600 Buchungen samt Begründungen
        // ein paar hundert Kilobyte — das darf die Geste nicht anhalten.
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = data
        let file = file
        Task.detached(priority: .utility) {
            do {
                try file.save(snapshot)
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, generation == self.saveGeneration else { return }
                    self.saveErrorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Für Tests: den aktuellen Stand sofort schreiben.
    func flush() throws {
        try file.save(data)
    }
}

extension AppStore {
    /// Ein Speicher für die ganze App.
    ///
    /// Die Oberfläche und die Kurzbefehle greifen auf dieselbe Instanz zu. Ein
    /// Kurzbefehl, der im Hintergrund bucht, läuft im selben Prozess wie die Seite im
    /// Vordergrund — zwei getrennte Speicher würden sich gegenseitig überschreiben,
    /// und zwar genau dann, wenn beide dieselbe Datei für sich beanspruchen.
    static let shared = AppStore.loadFromDisk()

    /// Für Previews und den Simulator, ohne die echte Datei anzufassen.
    static var preview: AppStore {
        AppStore(data: SampleData.make(), file: DataFile(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("budget-preview-\(UUID().uuidString).json")))
    }
}
