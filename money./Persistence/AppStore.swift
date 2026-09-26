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
        MonthSummary.make(month: month, entries: data.entries, categories: data.categories)
    }

    func entries(of category: UUID, in month: YearMonth) -> [Entry] {
        data.entries.of(category: category, in: month)
    }

    /// Monate, in denen etwas steht — plus der laufende, damit man immer irgendwo steht.
    func recordedMonths(including month: YearMonth) -> Set<YearMonth> {
        data.entries.recordedMonths.union([month, .current()])
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

    var proposals: [Entry] { data.proposals }
    var hasProposals: Bool { data.entries.contains { $0.status == .proposed } }

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
              let original = data.entries.first(where: { $0.id == originalID }),
              original.kind == .flow, original.direction != .income else { return }
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
    /// Ausgabe alle Eingänge — ohne Zeitfenster, denn eine Rückzahlung kann Monate
    /// später kommen. Sortiert: gleicher Betrag zuerst, dann die zeitlich nächsten.
    func refundCandidates(for entry: Entry) -> [Entry] {
        let taken = Set(data.entries.compactMap(\.refundOf))
        let pool = data.entries.filter { other in
            guard other.id != entry.id, other.kind == .flow,
                  other.status != .proposed || other.source == .tradeRepublic
            else { return false }
            if entry.direction == .income {
                return other.direction != .income && !taken.contains(other.id)
            } else {
                return other.direction == .income && other.refundOf == nil
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
                entry.kind = .transfer
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
        let ids = data.proposals
            .filter { ($0.suggestion?.band ?? .unsure) != .unsure }
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

    private func mark(_ entry: Entry) {
        lastSaved = entry
        saveTick += 1
    }

    private func persist() {
        revision += 1
        do {
            try file.save(data)
        } catch {
            saveErrorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
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
