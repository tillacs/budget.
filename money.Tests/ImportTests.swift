import Foundation
import Testing
@testable import money_

/// Marker, um an die Fixture-Datei im Test-Bundle zu kommen.
private final class FixtureMarker {}

enum Fixture {
    static func tradeRepublic() throws -> String {
        let url = try #require(Bundle(for: FixtureMarker.self)
            .url(forResource: "TradeRepublicExport", withExtension: "csv"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func rows() throws -> [TradeRepublicExport.Row] {
        try TradeRepublicExport.parse(try tradeRepublic())
    }
}

/// Der Export von Trade Republic: 23 Spalten, alles in Anführungszeichen.
struct TradeRepublicParserTests {
    @Test func liestDieFixtureVollständig() throws {
        let rows = try Fixture.rows()
        #expect(rows.count == 1648)
        #expect(rows.allSatisfy { !$0.transactionID.isEmpty })
        #expect(Set(rows.map(\.transactionID)).count == rows.count)
    }

    @Test func liestBetragMCCUndGegenkonto() throws {
        let text = """
        "datetime","date","account_type","category","type","asset_class","name","symbol","shares","price","amount","fee","tax","currency","original_amount","original_currency","fx_rate","description","transaction_id","counterparty_name","counterparty_iban","payment_reference","mcc_code"
        "2026-08-04T12:05:45.598945Z","2026-08-04","DEFAULT","CASH","CARD_TRANSACTION","","EDEKA Muenchen. Impler","","","","-36.750000","","","EUR","","","","EDEKA MUENCHEN. IMPLER","id-1","","","","5411"
        "2026-08-03T06:59:18.008124Z","2026-08-03","DEFAULT","CASH","TRANSFER_INBOUND","","PayPal Europe S.a.r.l. et Cie S.C.A","","","","39.210000","","","EUR","","","","Incoming transfer from PayPal Europe S.a.r.l. et Cie S.C.A (LU89751000135104200E)","id-2","PayPal Europe S.a.r.l. et Cie S.C.A","LU89751000135104200E","",""
        "2025-11-17T00:00:00Z","2025-11-17","DEFAULT","CORPORATE_ACTION","SPLIT","STOCK","Netflix","US64110L1061","","","","","","EUR","","","","SPLIT US64110L1061","id-3","","","",""
        """
        let rows = try TradeRepublicExport.parse(text)
        #expect(rows.count == 3)
        #expect(rows[0].amount == Decimal(string: "-36.75"))
        #expect(rows[0].mcc == "5411")
        #expect(rows[0].date == CalendarDate(year: 2026, month: 8, day: 4))
        #expect(rows[1].counterpartyIBAN == "LU89751000135104200E")
        #expect(rows[2].amount == nil)
    }

    @Test func erkenntFremdeDateien() {
        #expect(throws: TradeRepublicExport.ParseError.self) {
            try TradeRepublicExport.parse("Datum;Betrag\n01.01.2026;12,50\n")
        }
        #expect(throws: TradeRepublicExport.ParseError.empty) {
            try TradeRepublicExport.parse("")
        }
    }

    @Test func csvKenntAnführungszeichenUndZeilenumbrüche() {
        let table = CSV.parse("\"a,b\",\"sagt \"\"hallo\"\"\",c\r\n1,\"zwei\nzeilen\",3\n")
        #expect(table == [["a,b", "sagt \"hallo\"", "c"], ["1", "zwei\nzeilen", "3"]])
    }
}

struct MerchantTokenTests {
    @Test func zerlegtHändlerInWörter() {
        #expect(MerchantKey.tokens("EDEKA MUENCHEN. IMPLER") == ["edeka", "impler"])
        #expect(MerchantKey.tokens("DM DROGERIE SAGT DANKE") == ["drogerie"])
        #expect(MerchantKey.tokens("PAYPAL *OPENAI *CHATGPT S") == ["openai", "chatgpt"])
        #expect(MerchantKey.tokens("Tegut Filiale 2880") == ["tegut"])
    }

    @Test func filialnummernMachenKeinenNeuenHändler() {
        #expect(MerchantKey.normalized("Tegut Filiale 2880") == MerchantKey.normalized("Tegut Filiale 2881"))
        #expect(MerchantKey.normalized("PAYPAL *nutzer1") == "NUTZER1")
    }

    @Test func machtBelegeLesbar() {
        #expect(MerchantKey.displayName("EDEKA MUENCHEN. IMPLER") == "Edeka Muenchen. Impler")
        #expect(MerchantKey.displayName("PAYPAL *nutzer1") == "nutzer1")
        #expect(MerchantKey.displayName("DB Vertrieb GmbH") == "DB Vertrieb GmbH")
    }
}

/// Die sieben Regeln gegen Dopplungen — jede mit ihrem Test.
struct ImportPipelineTests {
    private func header() -> String {
        "\"datetime\",\"date\",\"account_type\",\"category\",\"type\",\"asset_class\",\"name\",\"symbol\",\"shares\",\"price\",\"amount\",\"fee\",\"tax\",\"currency\",\"original_amount\",\"original_currency\",\"fx_rate\",\"description\",\"transaction_id\",\"counterparty_name\",\"counterparty_iban\",\"payment_reference\",\"mcc_code\"\n"
    }

    private func card(_ id: String, _ date: String, _ amount: String, _ name: String, mcc: String = "5411") -> String {
        "\"\(date)T10:00:00Z\",\"\(date)\",\"DEFAULT\",\"CASH\",\"CARD_TRANSACTION\",\"\",\"\(name)\",\"\",\"\",\"\",\"\(amount)\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"\(name.uppercased())\",\"\(id)\",\"\",\"\",\"\",\"\(mcc)\"\n"
    }

    private func transfer(_ id: String, _ date: String, _ amount: String, _ type: String, _ name: String, iban: String) -> String {
        let verb = amount.hasPrefix("-") ? "Outgoing transfer for" : "Incoming transfer from"
        return "\"\(date)T10:00:00Z\",\"\(date)\",\"DEFAULT\",\"CASH\",\"\(type)\",\"\",\"\(name)\",\"\",\"\",\"\",\"\(amount)\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"\(verb) \(name) (\(iban))\",\"\(id)\",\"\(name)\",\"\(iban)\",\"\",\"\"\n"
    }

    private func rows(_ body: String) throws -> [TradeRepublicExport.Row] {
        try TradeRepublicExport.parse(header() + body)
    }

    private func category(_ data: AppData, _ name: String, _ direction: Direction = .expense) throws -> BudgetCategory {
        try #require(data.categories.first { $0.name == name && $0.direction == direction })
    }

    // Regel 2 + Prüfsumme, am ganzen Export.
    @Test func zweiterImportÄndertNichtsUndDiePrüfsummeStimmt() throws {
        let rows = try Fixture.rows()
        let first = ImportPipeline.run(rows: rows, into: .seeded())
        #expect(first.report.rows == 1648)
        #expect(first.report.alreadyKnown == 0)
        #expect(first.report.isBalanced, "Differenzen: \(first.report.checksum.filter { $0.value != 0 })")
        #expect(first.report.imported + first.report.withoutAmount == 1648)
        #expect(first.report.savebackPairs >= 8)
        #expect(first.report.refundsLinked > 0)

        let second = ImportPipeline.run(rows: rows, into: first.data)
        #expect(second.data.entries.count == first.data.entries.count)
        #expect(second.report.alreadyKnown == 1648 - first.report.withoutAmount)
        #expect(second.report.imported == 0)
        #expect(second.report.isBalanced)
        for month in Set(first.data.entries.map(\.month)) {
            let a = MonthSummary.make(month: month, entries: first.data.entries, categories: first.data.categories)
            let b = MonthSummary.make(month: month, entries: second.data.entries, categories: second.data.categories)
            #expect(a.expenses.total == b.expenses.total)
            #expect(a.income.total == b.income.total)
            #expect(a.invested.total == b.invested.total)
        }
    }

    // Regel 7: gleich ist nicht doppelt.
    @Test func gleicheBeträgeMitVerschiedenenIDsSindZweiBuchungen() throws {
        let body = card("a", "2026-06-18", "-7.000000", "PAYPAL *nutzer5", mcc: "4829")
            + card("b", "2026-06-18", "-7.000000", "PAYPAL *nutzer5", mcc: "4829")
        let outcome = ImportPipeline.run(rows: try rows(body), into: .seeded())
        #expect(outcome.data.entries.count == 2)
    }

    // Regel 5: Erstattung senkt die Kategorie, statt Einnahme zu sein.
    @Test func erstattungWirdVerknüpftUndSenktDieKategorie() throws {
        var data = AppData.seeded()
        let shopping = try category(data, "Shopping")
        let body = card("kauf", "2026-08-21", "-393.390000", "WWW.BARRABES.COM", mcc: "5941")
        data = ImportPipeline.run(rows: try rows(body), into: data).data
        // Der Nutzer bestätigt den Kauf als Shopping.
        var kauf = try #require(data.entries.first)
        kauf.categoryID = shopping.id
        kauf.status = .confirmed
        data.entries[0] = kauf

        let refund = card("rueck", "2026-08-23", "393.390000", "WWW.BARRABES.COM", mcc: "5941")
        let outcome = ImportPipeline.run(rows: try rows(refund), into: data)
        #expect(outcome.report.refundsLinked == 1)
        let erstattung = try #require(outcome.data.entries.first { $0.externalID == "rueck" })
        #expect(erstattung.kind == .refund)
        #expect(erstattung.refundOf == kauf.id)
        #expect(erstattung.categoryID == shopping.id)
        #expect(erstattung.status == .autoBooked)

        let month = YearMonth(year: 2026, month: 8)
        let summary = MonthSummary.make(month: month, entries: outcome.data.entries, categories: outcome.data.categories)
        #expect(summary.expenses.total == 0)
        #expect(summary.income.total == 0)
        #expect(outcome.report.isBalanced)
    }

    @Test func erstattungOhneAusgabeWirdGefragt() throws {
        let outcome = ImportPipeline.run(
            rows: try rows(card("r", "2026-08-23", "50.900000", "SP GREEN ROOM HEADWEAR", mcc: "5699")),
            into: .seeded())
        let entry = try #require(outcome.data.entries.first)
        #expect(entry.kind == .refund)
        #expect(entry.status == .proposed)
        #expect(entry.suggestion?.evidence.first?.kind == .refund)
    }

    // Regel 6: Überweisung an sich selbst ist eine Umbuchung.
    @Test func überweisungAnSichSelbstIstUmbuchung() throws {
        var data = AppData.seeded()
        data.ownerName = "Till Kokemoor"
        let body = transfer("t1", "2026-07-10", "-1620.000000", "TRANSFER_INSTANT_OUTBOUND", "Till Kokemoor", iban: "DE12100110012625980979")
            + transfer("t2", "2026-07-11", "-97.000000", "TRANSFER_INSTANT_OUTBOUND", "Person 3", iban: "DE65100123452297955811")
        let outcome = ImportPipeline.run(rows: try rows(body), into: data)
        #expect(outcome.report.transfers == 1)
        let eigen = try #require(outcome.data.entries.first { $0.externalID == "t1" })
        #expect(eigen.kind == .transfer)
        #expect(eigen.status == .confirmed)
        let fremd = try #require(outcome.data.entries.first { $0.externalID == "t2" })
        #expect(fremd.kind == .flow)
        #expect(fremd.status == .proposed)
        let summary = MonthSummary.make(month: YearMonth(year: 2026, month: 7), entries: outcome.data.entries, categories: outcome.data.categories)
        #expect(summary.transferTotal == 1620)
        #expect(summary.expenses.total == 0)
        #expect(outcome.report.isBalanced)
    }

    /// „35 € für Unterwegs ausgegeben, 35 € vom Vater bekommen": Der Eingang wird
    /// als Ausgleich vorgeschlagen und senkt die Ausgabe, statt Einnahme zu sein.
    @MainActor @Test func geldVonPersonWirdAlsAusgleichVorgeschlagen() throws {
        var data = AppData.seeded()
        let unterwegs = try category(data, "Unterwegs")
        data.entries.append(Entry(
            date: CalendarDate(year: 2026, month: 9, day: 10), amount: 35,
            direction: .expense, categoryID: unterwegs.id, note: "Zugticket"))
        let body = transfer("v1", "2026-09-12", "35.000000", "TRANSFER_INBOUND", "Person 1", iban: "DE11100000000000000000")
        let outcome = ImportPipeline.run(rows: try rows(body), into: data)
        let eingang = try #require(outcome.data.entries.first { $0.externalID == "v1" })
        #expect(eingang.kind == .refund)
        #expect(eingang.status == .proposed)
        #expect(eingang.refundOf == data.entries[0].id)
        #expect(eingang.suggestion?.isGuess == false)
        #expect(outcome.report.isBalanced)

        // Angenommen: Unterwegs steht bei null, Einnahmen bleiben leer.
        let store = AppStore(data: outcome.data, file: DataFile(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("budget-ausgleich-\(UUID().uuidString).json")))
        store.accept(eingang.id)
        let summary = store.summary(for: YearMonth(year: 2026, month: 9))
        #expect(summary.expenses.total == 0)
        #expect(summary.income.total == 0)

        // Gelöst: wieder ein offener Eingang, die Ausgabe zählt wieder.
        store.unlinkRefund(eingang.id)
        #expect(store.entry(eingang.id)?.kind == .flow)
        #expect(store.entry(eingang.id)?.status == .proposed)
        #expect(store.summary(for: YearMonth(year: 2026, month: 9)).expenses.total == 35)
    }

    /// Der Vater schickt 50 Cent mehr — trotzdem ein Ausgleich.
    @Test func ausgleichVerträgtKleineAbweichungen() throws {
        var data = AppData.seeded()
        let unterwegs = try category(data, "Unterwegs")
        data.entries.append(Entry(
            date: CalendarDate(year: 2026, month: 9, day: 10), amount: 35,
            direction: .expense, categoryID: unterwegs.id, note: "Zugticket"))
        let body = transfer("v2", "2026-09-12", "35.500000", "TRANSFER_INBOUND", "Person 1", iban: "DE11100000000000000000")
        let outcome = ImportPipeline.run(rows: try rows(body), into: data)
        let eingang = try #require(outcome.data.entries.first { $0.externalID == "v2" })
        #expect(eingang.kind == .refund)
        #expect(eingang.suggestion?.reason.contains("fast gleicher") == true)
        #expect(Decimal(35).roughlyEquals(Decimal(string: "35.5")!))
        #expect(!Decimal(35).roughlyEquals(Decimal(40)))
        #expect(Decimal(500).roughlyEquals(Decimal(520)))
    }

    /// 32 € für zwei bezahlt, 16 € kommen im nächsten Monat zurück: Die Ausgabe steht
    /// bei 16 € — in ihrem Monat, nicht im Monat des Eingangs.
    @MainActor @Test func teilausgleichSenktDieAusgabeInIhremMonat() throws {
        let store = AppStore(data: .seeded(), file: DataFile(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("budget-anteil-\(UUID().uuidString).json")))
        let essen = try #require(store.data.categories.first { $0.name == "Essen" })
        let gehalt = try #require(store.data.categories.first { $0.name == "Gehalt" })
        let dinner = Entry(date: CalendarDate(year: 2026, month: 8, day: 30), amount: 32,
                           direction: .expense, categoryID: essen.id, note: "Pizza zu zweit")
        let back = Entry(date: CalendarDate(year: 2026, month: 9, day: 2), amount: 16,
                         direction: .income, categoryID: gehalt.id, note: "Freund")
        store.add(dinner)
        store.add(back)

        store.linkRefund(back.id, to: dinner.id)

        let august = store.summary(for: YearMonth(year: 2026, month: 8))
        #expect(august.expenses.total == 16)
        #expect(august.expenses.slices.first?.count == 1)
        let september = store.summary(for: YearMonth(year: 2026, month: 9))
        #expect(september.expenses.total == 0)
        #expect(september.income.total == 0)
        #expect(september.neutralCount == 1)
        #expect(store.netAmount(of: dinner) == 16)
        #expect(store.refunds(of: dinner.id).map(\.id) == [back.id])
        // In der Kategorienliste steht der Ausgleich nicht mehr für sich.
        #expect(store.entries(of: essen.id, in: YearMonth(year: 2026, month: 8)).count == 1)

        // Voll ausgeglichen: Die Kategorie bleibt mit ihrer Buchung stehen, bei null.
        let rest = Entry(date: CalendarDate(year: 2026, month: 9, day: 3), amount: 16,
                         direction: .income, categoryID: gehalt.id, note: "Freund, Rest")
        store.add(rest)
        store.linkRefund(rest.id, to: dinner.id)
        let balanced = store.summary(for: YearMonth(year: 2026, month: 8))
        #expect(balanced.expenses.total == 0)
        #expect(balanced.expenses.slices.first?.category.id == essen.id)
        #expect(balanced.expenses.slices.first?.count == 1)
        #expect(store.netAmount(of: dinner) == 0)
    }

    /// Ein Ausgleich, der nach Neutral wandert, behält das echte Vorzeichen: Das
    /// Geld kam rein, also steht es unter Neutral als Eingang.
    @MainActor @Test func neutralBehältDasVorzeichenDesGeldes() throws {
        let store = AppStore(data: .seeded(), file: DataFile(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("budget-vorzeichen-\(UUID().uuidString).json")))
        let essen = try #require(store.data.categories.first { $0.name == "Essen" })
        let gehalt = try #require(store.data.categories.first { $0.name == "Gehalt" })
        let dinner = Entry(amount: 32, direction: .expense, categoryID: essen.id, note: "Pizza")
        let back = Entry(amount: 16, direction: .income, categoryID: gehalt.id, note: "PayPal",
                         source: .tradeRepublic, externalID: "pp", importType: "TRANSFER_INBOUND")
        store.add(dinner)
        store.add(back)
        store.linkRefund(back.id, to: dinner.id)
        #expect(store.entry(back.id)?.direction == .expense)   // Ausgleich: Ausgabenseite
        #expect(store.entry(back.id)?.signedAmount == 16)       // aber Geld kam rein

        store.reject(back.id, as: .transfer)
        let neutral = try #require(store.entry(back.id))
        #expect(neutral.kind == .transfer)
        #expect(neutral.signedAmount == 16)

        // Alte Daten mit verlorenem Vorzeichen werden beim Laden repariert.
        var broken = neutral
        broken.direction = .expense
        store.update(broken)
        store.repairTransferDirections()
        #expect(store.entry(back.id)?.signedAmount == 16)
    }

    /// Das echte Vorzeichen kommt aus dem Export und ist unantastbar: keine
    /// Kategorie der falschen Seite, kein Ausgleich mit ausgehendem Geld.
    @MainActor @Test func dasEchteVorzeichenBleibt() throws {
        let store = AppStore(data: .seeded(), file: DataFile(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("budget-fakt-\(UUID().uuidString).json")))
        let csv = """
        "datetime","date","account_type","category","type","asset_class","name","symbol","shares","price","amount","fee","tax","currency","original_amount","original_currency","fx_rate","description","transaction_id","counterparty_name","counterparty_iban","payment_reference","mcc_code"
        "2026-09-04T12:05:45Z","2026-09-04","DEFAULT","CASH","CARD_TRANSACTION","","ALDI SUED","","","","-21.300000","","","EUR","","","","ALDI SUED","a1","","","","5411"
        "2026-09-05T12:05:45Z","2026-09-05","DEFAULT","CASH","TRANSFER_INBOUND","","Max Muster","","","","40.000000","","","EUR","","","","Incoming transfer from Max Muster","t1","Max Muster","DE11","",""
        """
        try store.importTradeRepublic(csv)
        let aldi = try #require(store.data.entries.first { $0.externalID == "a1" })
        let max = try #require(store.data.entries.first { $0.externalID == "t1" })
        #expect(aldi.inflow == false)
        #expect(max.inflow == true)

        let gehalt = try #require(store.data.categories.first { $0.name == "Gehalt" })
        let essen = try #require(store.data.categories.first { $0.name == "Essen" })
        store.correct(aldi.id, to: gehalt.id)          // falsche Seite: passiert nichts
        #expect(store.entry(aldi.id)?.status == .proposed)
        store.correct(max.id, to: essen.id)            // falsche Seite: passiert nichts
        #expect(store.entry(max.id)?.direction == .income)
        store.linkRefund(aldi.id, to: max.id)          // Ausgabe kann nichts ausgleichen
        #expect(store.entry(aldi.id)?.kind == .flow)

        store.reject(max.id, as: .transfer)
        #expect(store.entry(max.id)?.signedAmount == 40)
        store.reject(aldi.id, as: .transfer)
        #expect(store.entry(aldi.id)?.signedAmount == Decimal(string: "-21.3"))
    }

    /// Das Geld kann auch vor der Ausgabe kommen: Der Freund überweist, danach zahlt man.
    @Test func ausgleichAuchWennDasGeldZuerstKam() throws {
        var data = AppData.seeded()
        let essen = try category(data, "Essen")
        data.entries.append(Entry(
            date: CalendarDate(year: 2026, month: 9, day: 20), amount: 24,
            direction: .expense, categoryID: essen.id, note: "Kino zu zweit"))
        let body = transfer("v3", "2026-09-15", "24.000000", "TRANSFER_INBOUND", "Person 1", iban: "DE11100000000000000000")
        let outcome = ImportPipeline.run(rows: try rows(body), into: data)
        let eingang = try #require(outcome.data.entries.first { $0.externalID == "v3" })
        #expect(eingang.kind == .refund)
        #expect(eingang.refundOf == data.entries[0].id)
    }

    /// Ein Eingang, der versehentlich in Neutral liegt, taucht in der Auswahl auf
    /// und lässt sich von dort als Ausgleich holen.
    @MainActor @Test func ausgleichAuswahlZeigtAuchNeutrales() throws {
        let store = AppStore(data: .seeded(), file: DataFile(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("budget-alle-\(UUID().uuidString).json")))
        let essen = try #require(store.data.categories.first { $0.name == "Essen" })
        let gehalt = try #require(store.data.categories.first { $0.name == "Gehalt" })
        let pizza = Entry(amount: 32, direction: .expense, categoryID: essen.id, note: "Pizza")
        let back = Entry(amount: 16, direction: .income, categoryID: gehalt.id, note: "Freund",
                         source: .tradeRepublic, externalID: "x", importType: "TRANSFER_INBOUND", inflow: true)
        store.add(pizza); store.add(back)
        store.reject(back.id, as: .transfer)
        #expect(store.entry(back.id)?.kind == .transfer)

        #expect(store.refundCandidates(for: pizza).map(\.id).contains(back.id))
        store.linkRefund(back.id, to: pizza.id)
        #expect(store.entry(back.id)?.kind == .refund)
        #expect(store.entry(back.id)?.refundOf == pizza.id)
        #expect(store.netAmount(of: pizza) == 16)
    }

    @Test func eigeneIBANZähltAuchOhneNamen() throws {
        var data = AppData.seeded()
        data.ownIBANs = ["DE12100110012625980979"]
        let body = transfer("t1", "2026-07-10", "-30.000000", "TRANSFER_OUTBOUND", "Irgendwer", iban: "DE12100110012625980979")
        let outcome = ImportPipeline.run(rows: try rows(body), into: data)
        #expect(outcome.data.entries.first?.kind == .transfer)
    }

    // Regel 3: Eine Buchung von Hand wird vom Export eingelöst, nicht verdoppelt.
    @Test func buchungVonHandWirdÜbernommen() throws {
        var data = AppData.seeded()
        let lebensmittel = try category(data, "Lebensmittel")
        data.entries.append(Entry(
            date: CalendarDate(year: 2026, month: 8, day: 4), amount: Decimal(string: "36.75")!,
            direction: .expense, categoryID: lebensmittel.id, note: "Edeka"))
        let outcome = ImportPipeline.run(
            rows: try rows(card("e", "2026-08-05", "-36.750000", "EDEKA Muenchen. Impler")), into: data)
        #expect(outcome.report.adopted == 1)
        #expect(outcome.data.entries.count == 1)
        let entry = try #require(outcome.data.entries.first)
        #expect(entry.externalID == "e")
        #expect(entry.categoryID == lebensmittel.id)
        #expect(entry.status == .confirmed)
        // Das gilt als Bestätigung: Der Händler ist jetzt bekannt.
        #expect(outcome.data.memory.topCategory(forMerchant: "EDEKA Ebenhausen") == nil)
        #expect(outcome.data.memory.topCategory(forMerchant: "EDEKA Muenchen. Impler") == lebensmittel.id)
    }

    // Saveback: Gutschrift und Kauf gehören zusammen, beide zählen — einmal.
    @Test func savebackWirdGepaart() throws {
        let body = "\"2025-08-04T10:00:00Z\",\"2025-08-04\",\"DEFAULT\",\"CASH\",\"BENEFITS_SAVEBACK\",\"STOCK\",\"TSMC (ADR)\",\"US8740391003\",\"\",\"\",\"15.000000\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"Your Saveback payment\",\"sb\",\"\",\"\",\"\",\"\"\n"
            + "\"2025-08-04T10:01:00Z\",\"2025-08-04\",\"DEFAULT\",\"TRADING\",\"BUY\",\"STOCK\",\"TSMC (ADR)\",\"US8740391003\",\"0.06\",\"250\",\"-15.00\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"Savings plan execution US8740391003 TSMC\",\"buy\",\"\",\"\",\"\",\"\"\n"
        let outcome = ImportPipeline.run(rows: try rows(body), into: .seeded())
        #expect(outcome.report.savebackPairs == 1)
        let credit = try #require(outcome.data.entries.first { $0.externalID == "sb" })
        let buy = try #require(outcome.data.entries.first { $0.externalID == "buy" })
        #expect(credit.direction == .income)
        #expect(buy.direction == .invest)
        #expect(buy.importType == "BUY_SAVEBACK")
        #expect(credit.pairedWith == buy.id && buy.pairedWith == credit.id)
        #expect(outcome.data.category(buy.categoryID)?.name == "Saveback")
        #expect(outcome.data.category(credit.categoryID)?.name == "Saveback")
        #expect(outcome.report.isBalanced)
    }

    /// Seit Ende 2025 kommt der Saveback-Kauf ein bis drei Tage nach der Gutschrift.
    @Test func savebackPaartAuchDenKaufTageSpäter() throws {
        let body = "\"2026-03-01T06:00:00Z\",\"2026-03-01\",\"DEFAULT\",\"CASH\",\"BENEFITS_SAVEBACK\",\"\",\"\",\"\",\"\",\"\",\"11.350000\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\" Saveback cash reward b683\",\"sb\",\"\",\"\",\"\",\"\"\n"
            + "\"2026-03-02T10:01:00Z\",\"2026-03-02\",\"DEFAULT\",\"TRADING\",\"BUY\",\"STOCK\",\"BMW\",\"DE0005190003\",\"0.1\",\"113\",\"-11.35\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"Savings plan execution DE0005190003 BMW\",\"buy\",\"\",\"\",\"\",\"\"\n"
            + "\"2026-03-02T10:02:00Z\",\"2026-03-02\",\"DEFAULT\",\"TRADING\",\"BUY\",\"FUND\",\"Core MSCI World\",\"IE00B4L5Y983\",\"0.1\",\"100\",\"-50.00\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"Savings plan execution IE00B4L5Y983\",\"sp\",\"\",\"\",\"\",\"\"\n"
        let outcome = ImportPipeline.run(rows: try rows(body), into: .seeded())
        #expect(outcome.report.savebackPairs == 1)
        let buy = try #require(outcome.data.entries.first { $0.externalID == "buy" })
        let plan = try #require(outcome.data.entries.first { $0.externalID == "sp" })
        #expect(outcome.data.category(buy.categoryID)?.name == "Saveback")
        #expect(outcome.data.category(plan.categoryID)?.name == "Sparplan")
    }

    @Test func sparplanUndZinsenBekommenIhreKategorien() throws {
        let body = "\"2025-08-04T10:01:00Z\",\"2025-08-04\",\"DEFAULT\",\"TRADING\",\"BUY\",\"FUND\",\"Core MSCI World\",\"IE00B4L5Y983\",\"0.1\",\"100\",\"-10.00\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"Savings plan execution IE00B4L5Y983\",\"sp\",\"\",\"\",\"\",\"\"\n"
            + "\"2025-08-01T07:21:40Z\",\"2025-08-01\",\"DEFAULT\",\"CASH\",\"INTEREST_PAYMENT\",\"\",\"\",\"\",\"\",\"\",\"1.940000\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"Interest payment for payout collection x\",\"int\",\"\",\"\",\"\",\"\"\n"
        var data = AppData(categories: Seed.categories().filter { $0.direction == .expense })
        data = ImportPipeline.run(rows: try rows(body), into: data).data
        let sparplan = try #require(data.entries.first { $0.externalID == "sp" })
        #expect(data.category(sparplan.categoryID)?.name == "Sparplan")
        #expect(sparplan.suggestion?.band == .likely || sparplan.suggestion?.band == .sure)
        let zinsen = try #require(data.entries.first { $0.externalID == "int" })
        #expect(data.category(zinsen.categoryID)?.name == "Kapitalerträge")
    }

    @Test func zeilenOhneGeldWerdenGemerktNichtGebucht() throws {
        let body = "\"2025-11-17T00:00:00Z\",\"2025-11-17\",\"DEFAULT\",\"CORPORATE_ACTION\",\"SPLIT\",\"STOCK\",\"Netflix\",\"US64110L1061\",\"\",\"\",\"\",\"\",\"\",\"EUR\",\"\",\"\",\"\",\"SPLIT\",\"split\",\"\",\"\",\"\",\"\"\n"
        let outcome = ImportPipeline.run(rows: try rows(body), into: .seeded())
        #expect(outcome.data.entries.isEmpty)
        #expect(outcome.report.withoutAmount == 1)
        #expect(outcome.data.ignoredExternalIDs == ["split"])
        let again = ImportPipeline.run(rows: try rows(body), into: outcome.data)
        #expect(again.report.withoutAmount == 0)
    }
}

/// Die Maschine: Vorschläge mit Konfidenz, die aus Bestätigungen wächst.
struct SuggestionEngineTests {
    private func draft(_ merchant: String, mcc: String? = "5411", amount: String = "12.50", day: Int = 10) -> Entry {
        Entry(date: CalendarDate(year: 2026, month: 9, day: day), amount: Decimal(string: amount)!,
              direction: .expense, categoryID: BudgetCategory.noneID, source: .tradeRepublic,
              merchant: merchant, mcc: mcc, importType: "CARD_TRANSACTION")
    }

    @Test func vorbelegungNachHändlercodeIstNurEinVorschlag() throws {
        let data = AppData.seeded()
        let ranking = try #require(SuggestionEngine.rank(
            draft("ALDI SUED"), categories: data.categories, memory: data.memory, lastUsed: nil, history: HistoryIndex()))
        #expect(data.category(ranking.suggestion.categoryID)?.name == "Lebensmittel")
        #expect(ranking.suggestion.band == .likely)
        #expect(ranking.autoEligible == false)
        #expect(ranking.suggestion.reason.contains("Supermarkt"))
    }

    @Test func ohneJedenAnhaltspunktBleibtEsUnsicher() throws {
        let data = AppData.seeded()
        let ranking = try #require(SuggestionEngine.rank(
            draft("Irgendwas", mcc: "7399"), categories: data.categories, memory: data.memory, lastUsed: nil, history: HistoryIndex()))
        #expect(ranking.suggestion.band == .unsure)
    }

    @Test func konfidenzWächstMitBestätigungenUndErlaubtAutomatikAbZwei() throws {
        var data = AppData.seeded()
        let essen = try #require(data.categories.first { $0.name == "Essen" })
        let d = draft("ALDI SUED")

        data.memory.confirm(d.signals, as: essen.id)
        var ranking = try #require(SuggestionEngine.rank(d, categories: data.categories, memory: data.memory, lastUsed: nil, history: HistoryIndex()))
        #expect(ranking.suggestion.categoryID == essen.id)
        #expect(ranking.autoEligible == false)
        #expect(ranking.suggestion.confidence < 0.9)

        data.memory.confirm(d.signals, as: essen.id)
        ranking = try #require(SuggestionEngine.rank(d, categories: data.categories, memory: data.memory, lastUsed: nil, history: HistoryIndex()))
        #expect(ranking.autoEligible)
        #expect(ranking.suggestion.confidence >= 0.9)
        #expect(ranking.suggestion.reason.contains("2×"))
    }

    @Test func ablehnungenZiehenDenVorschlagZurück() throws {
        var data = AppData.seeded()
        let essen = try #require(data.categories.first { $0.name == "Essen" })
        let d = draft("ALDI SUED")
        data.memory.confirm(d.signals, as: essen.id)
        data.memory.reject(d.signals, as: essen.id)
        let ranking = try #require(SuggestionEngine.rank(d, categories: data.categories, memory: data.memory, lastUsed: nil, history: HistoryIndex()))
        #expect(ranking.suggestion.categoryID != essen.id)
    }

    @Test func wörterTragenAufNeueFilialen() throws {
        var data = AppData.seeded()
        let lebensmittel = try #require(data.categories.first { $0.name == "Lebensmittel" })
        for _ in 0..<3 { data.memory.confirm(draft("EDEKA Muenchen. Impler").signals, as: lebensmittel.id) }
        let ranking = try #require(SuggestionEngine.rank(
            draft("EDEKA Ebenhausen", mcc: nil), categories: data.categories, memory: data.memory, lastUsed: nil, history: HistoryIndex()))
        #expect(ranking.suggestion.categoryID == lebensmittel.id)
        #expect(ranking.suggestion.evidence.contains { $0.kind == .token })
        // Neue Filiale: noch nie bestätigt, also keine Automatik.
        #expect(ranking.autoEligible == false)
    }

    @Test func zweiGleichStarkeKandidatenSenkenDieKonfidenz() throws {
        var data = AppData.seeded()
        let essen = try #require(data.categories.first { $0.name == "Essen" })
        let lebensmittel = try #require(data.categories.first { $0.name == "Lebensmittel" })
        let d = draft("Hoereder Beck", mcc: "5462")
        data.memory.confirm(d.signals, as: essen.id)
        data.memory.confirm(d.signals, as: lebensmittel.id)
        let ranking = try #require(SuggestionEngine.rank(d, categories: data.categories, memory: data.memory, lastUsed: nil, history: HistoryIndex()))
        // Der Händler selbst sagt nichts mehr; der Händlercode gibt den Ausschlag —
        // aber ohne klare Bestätigung bucht die Maschine nicht von allein.
        #expect(ranking.suggestion.evidence.allSatisfy { $0.kind != .merchant })
        #expect(ranking.autoEligible == false)
        #expect(ranking.suggestion.categoryID == lebensmittel.id)
        #expect(ranking.suggestion.alternatives.contains(essen.id))
    }

    /// Eine Überweisung der Eltern hat mit der letzten Dividende nichts zu tun:
    /// ohne Gelerntes gibt es keinen Vorschlag, nur die offene Frage.
    @Test func überweisungenFallenNichtAufZuletztBenutztZurück() throws {
        let data = AppData.seeded()
        let kapital = try #require(data.categories.first { $0.name == "Kapitalerträge" })
        var transfer = Entry(date: CalendarDate(year: 2026, month: 9, day: 3), amount: 500,
                             direction: .income, categoryID: BudgetCategory.noneID, source: .tradeRepublic,
                             merchant: "Mutter Muster", importType: "TRANSFER_INBOUND")
        let ranking = try #require(SuggestionEngine.rank(
            transfer, categories: data.categories, memory: data.memory, lastUsed: kapital.id, history: HistoryIndex()))
        #expect(ranking.suggestion.isGuess)
        #expect(ranking.suggestion.confidence == 0)

        // Eine Kartenzahlung darf dagegen auf zuletzt benutzt zurückfallen.
        transfer.importType = "CARD_TRANSACTION"
        transfer.direction = .expense
        let essen = try #require(data.categories.first { $0.name == "Essen" })
        let card = try #require(SuggestionEngine.rank(
            transfer, categories: data.categories, memory: data.memory, lastUsed: essen.id, history: HistoryIndex()))
        #expect(card.suggestion.isGuess == false)
    }

    /// Menschen sind keine Regel: Vorschlag ja, mit Verteilung, aber nie Automatik
    /// und nie „sicher". Firmen dagegen schon.
    @Test func menschenBekommenSchwacheVorschlägeOhneAutomatik() throws {
        var data = AppData.seeded()
        let gehalt = try #require(data.categories.first { $0.name == "Gehalt" })
        let sonstiges = try #require(data.categories.first { $0.name == "Sonstiges" })
        let vater = Entry(date: CalendarDate(year: 2026, month: 9, day: 3), amount: 100,
                          direction: .income, categoryID: BudgetCategory.noneID, source: .tradeRepublic,
                          merchant: "Max Muster", counterpartyIBAN: "DE11", importType: "TRANSFER_INBOUND")
        #expect(vater.isPersonal)
        #expect(vater.signals.tokens.isEmpty)
        for _ in 0..<5 { data.memory.confirm(vater.signals, as: gehalt.id) }
        data.memory.confirm(vater.signals, as: sonstiges.id)

        let ranking = try #require(SuggestionEngine.rank(
            vater, categories: data.categories, memory: data.memory, lastUsed: nil, history: HistoryIndex()))
        #expect(ranking.suggestion.categoryID == gehalt.id)
        #expect(ranking.autoEligible == false)
        #expect(ranking.suggestion.band != .sure)
        #expect(ranking.suggestion.reason.contains("5× Gehalt"))
        #expect(ranking.suggestion.reason.contains("1× Sonstiges"))
        #expect(ranking.suggestion.alternatives.first == sonstiges.id)

        let firma = Entry(date: CalendarDate(year: 2026, month: 9, day: 1), amount: 2400,
                          direction: .income, categoryID: BudgetCategory.noneID, source: .tradeRepublic,
                          merchant: "Beispiel GmbH", importType: "TRANSFER_INBOUND")
        #expect(firma.isPersonal == false)
        var memory = MerchantMemory()
        memory.confirm(firma.signals, as: gehalt.id)
        memory.confirm(firma.signals, as: gehalt.id)
        let salary = try #require(SuggestionEngine.rank(
            firma, categories: data.categories, memory: memory, lastUsed: nil, history: HistoryIndex()))
        #expect(salary.autoEligible)
        #expect(salary.suggestion.band == .sure)
    }

    @Test func erkenntOrganisationen() {
        #expect(MerchantKey.looksLikeOrganization("Beispiel GmbH"))
        #expect(MerchantKey.looksLikeOrganization("Staatsoberkasse Bayern in Landshut"))
        #expect(MerchantKey.looksLikeOrganization("PayPal Europe"))
        #expect(!MerchantKey.looksLikeOrganization("Max Muster"))
        #expect(!MerchantKey.looksLikeOrganization("Dr. Anna Beispiel"))
    }

    @Test func wiederkehrendesGibtEinenSchub() throws {
        var data = AppData.seeded()
        let abos = try #require(data.categories.first { $0.name == "Abos" })
        var previous = draft("fraenk", mcc: "4814", amount: "10.00", day: 10)
        previous.date = CalendarDate(year: 2026, month: 8, day: 10)
        previous.categoryID = abos.id
        previous.status = .confirmed
        data.memory.confirm(previous.signals, as: abos.id)
        let ranking = try #require(SuggestionEngine.rank(
            draft("fraenk", mcc: "4814", amount: "10.00", day: 10),
            categories: data.categories, memory: data.memory, lastUsed: nil, history: HistoryIndex([previous])))
        #expect(ranking.suggestion.evidence.contains { $0.kind == .recurring })
        #expect(ranking.suggestion.confidence >= 0.9)
    }
}

@MainActor
struct InboxStoreTests {
    private func store() -> AppStore {
        AppStore(data: .seeded(), file: DataFile(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("budget-inbox-\(UUID().uuidString).json")))
    }

    private let csv = """
    "datetime","date","account_type","category","type","asset_class","name","symbol","shares","price","amount","fee","tax","currency","original_amount","original_currency","fx_rate","description","transaction_id","counterparty_name","counterparty_iban","payment_reference","mcc_code"
    "2026-09-04T12:05:45Z","2026-09-04","DEFAULT","CASH","CARD_TRANSACTION","","ALDI SUED","","","","-21.300000","","","EUR","","","","ALDI SUED","a1","","","","5411"
    "2026-09-05T12:05:45Z","2026-09-05","DEFAULT","CASH","CARD_TRANSACTION","","Irgendein Laden","","","","-9.000000","","","EUR","","","","IRGENDEIN LADEN","b1","","","","7399"
    """

    @Test func annehmenKorrigierenAblehnenLernen() throws {
        let store = store()
        let report = try store.importTradeRepublic(csv)
        #expect(report.proposed == 2)
        #expect(store.proposals.count == 2)

        let aldi = try #require(store.proposals.first { $0.externalID == "a1" })
        let laden = try #require(store.proposals.first { $0.externalID == "b1" })
        let essen = try #require(store.data.categories.first { $0.name == "Freizeit" })

        store.accept(aldi.id)
        #expect(store.entry(aldi.id)?.status == .confirmed)
        #expect(store.data.memory.topCategory(forMerchant: "ALDI SUED") == aldi.categoryID)

        store.correct(laden.id, to: essen.id)
        #expect(store.entry(laden.id)?.categoryID == essen.id)
        #expect(store.entry(laden.id)?.suggestion?.decision == .corrected(essen.id))
        #expect(store.proposals.isEmpty)

        let summary = store.summary(for: YearMonth(year: 2026, month: 9))
        #expect(summary.expenses.total == Decimal(string: "30.3"))
    }

    @Test func verwerfenHältDieZeileBeimNächstenImportFern() throws {
        let store = store()
        try store.importTradeRepublic(csv)
        let laden = try #require(store.proposals.first { $0.externalID == "b1" })
        store.reject(laden.id, as: .delete)
        #expect(store.data.entries.count == 1)
        let again = try store.importTradeRepublic(csv)
        #expect(again.imported == 0)
        #expect(store.data.entries.count == 1)
    }

    @Test func alsUmbuchungAblehnenZähltNicht() throws {
        let store = store()
        try store.importTradeRepublic(csv)
        let laden = try #require(store.proposals.first { $0.externalID == "b1" })
        store.reject(laden.id, as: .transfer)
        store.acceptAllConfident()
        let summary = store.summary(for: YearMonth(year: 2026, month: 9))
        #expect(summary.expenses.total == Decimal(string: "21.3"))
        #expect(summary.transferCount == 1)
    }

    @Test func nachZweiBestätigungenBuchtDieMaschineSelbst() throws {
        let store = store()
        try store.importTradeRepublic(csv)
        store.acceptAllConfident()
        let lebensmittel = try #require(store.data.categories.first { $0.name == "Lebensmittel" })
        // Noch eine Bestätigung von Hand — dann sind es zwei.
        store.add(Entry(amount: 5, direction: .expense, categoryID: lebensmittel.id), merchant: "ALDI SUED")

        let more = """
        "datetime","date","account_type","category","type","asset_class","name","symbol","shares","price","amount","fee","tax","currency","original_amount","original_currency","fx_rate","description","transaction_id","counterparty_name","counterparty_iban","payment_reference","mcc_code"
        "2026-09-14T12:05:45Z","2026-09-14","DEFAULT","CASH","CARD_TRANSACTION","","ALDI SUED","","","","-14.000000","","","EUR","","","","ALDI SUED","a2","","","","5411"
        """
        let report = try store.importTradeRepublic(more)
        #expect(report.autoBooked == 1)
        #expect(store.entry(store.data.entries.first { $0.externalID == "a2" }?.id)?.status == .autoBooked)
    }

    /// Eine Datei aus Schema 2 kommt mit ihren Händlern an.
    @Test func schema2WirdÜbernommen() throws {
        let file = DataFile(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("budget-s2-\(UUID().uuidString).json"))
        defer { try? file.delete() }
        try FileManager.default.createDirectory(
            at: file.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let id = UUID()
        let alt = """
        {"schemaVersion":2,"entries":[],"categories":[{"id":"\(id.uuidString)","name":"Essen","symbol":"🍽️","tint":"azure","direction":"expense","sortIndex":0}],"lastUsed":{},"merchantCategories":{"REWE":"\(id.uuidString)"}}
        """
        try Data(alt.utf8).write(to: file.fileURL)
        let loaded = try #require(try file.load())
        #expect(loaded.schemaVersion == 3)
        #expect(loaded.rememberedCategory(forMerchant: "rewe")?.id == id)
        // Der Umstieg bringt die neuen Bereiche mit, ohne die eigene Kategorie anzufassen.
        #expect(loaded.categories.first { $0.name == "Essen" }?.id == id)
        #expect(loaded.categories.contains { $0.name == "Sparplan" && $0.direction == .invest })
        #expect(loaded.categories.contains { $0.name == "Kleidung" && $0.direction == .expense })
        #expect(loaded.categories.filter { $0.name == "Essen" }.count == 1)
    }
}
