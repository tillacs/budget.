// HomeScreen.swift
// budget. — die Seite, auf der alles steht
//
// Ein Pager über die Monate: Jeder Monat ist eine Seite — Monat, Saldo, die drei
// Summen, die Blasen, die Liste. Wischen blättert durch die Monate; erst hinter dem
// laufenden Monat liegt rechts die Seite mit Kategorien, Konten & Import.
// Der Posteingang sitzt oben links im Kopf, mit Zähler.
// Erfasst wird über das Blatt, das der Kurzbefehl öffnet — oder über das Plus.

import SwiftUI
import UniformTypeIdentifiers

enum HomeSheet: Identifiable, Hashable {
    case quickEntry(Direction)
    case edit(Entry)
    case inbox
    case detail(UUID)
    case report
    case link(Entry)
    case neutral

    var id: String {
        switch self {
        case .quickEntry(let direction): return "neu-\(direction.rawValue)"
        case .edit(let entry): return "bearbeiten-\(entry.id)"
        case .inbox: return "posteingang"
        case .detail(let id): return "detail-\(id)"
        case .report: return "bericht"
        case .link(let entry): return "ausgleich-\(entry.id)"
        case .neutral: return "neutral"
        }
    }
}

/// Eine Seite im Pager: ein Monat oder, ganz rechts, die Kategorien.
enum HomePage: Hashable {
    case month(YearMonth)
    case categories
}

struct HomeScreen: View {
    let store: AppStore

    @State private var page: HomePage = .month(.current())
    @State private var month: YearMonth = .current()
    @State private var selection: RingSelection?
    @State private var listDirection: Direction = .expense
    @State private var expanded: UUID?
    @State private var sheet: HomeSheet?
    @State private var flight: Flight?
    @Namespace private var totalsSlide
    @State private var pendingFlight: Flight?
    @State private var report: ImportReport?
    @State private var pickerFor: Entry?
    @State private var showsImporter = false
    @State private var importError: String?

    private let router = QuickEntryRouter.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Alle Monate vom frühesten mit Buchungen (mindestens ein Jahr zurück) bis heute.
    private var pageMonths: [YearMonth] {
        let current = YearMonth.current()
        let earliest = min(
            store.recordedMonths(including: month).min() ?? current,
            current.advanced(by: -11))
        var months: [YearMonth] = []
        var cursor = earliest
        while cursor <= current {
            months.append(cursor)
            cursor = cursor.advanced(by: 1)
        }
        return months
    }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(pageMonths, id: \.self) { m in
                    overview(for: m).tag(HomePage.month(m))
                }
                CategoriesPage(store: store) { withAnimation(motion) { page = .month(month) } }
                    .tag(HomePage.categories)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if let flight {
                SaveFlight(text: flight.text, tint: flight.tint) { self.flight = nil }
                    .transition(.identity)
            }
        }
        .tint(Palette.accent)
        .sheet(item: $sheet, content: sheetContent)
        .sheet(item: $pickerFor) { entry in
            CategoryPickerSheet(
                store: store, direction: entry.direction, current: entry.categoryID,
                allowed: entry.compatibleDirections
            ) {
                store.correct(entry.id, to: $0)
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.commaSeparatedText, .delimitedText, .plainText, .text]
        ) { result in
            do {
                try store.importTradeRepublic(try ImportFile.read(try result.get()))
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("Import nicht möglich", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .onChange(of: router.token) { openRequestedEntry() }
        .task { openRequestedEntry() }
        .onChange(of: store.saveTick) { takeOff() }
        .onChange(of: store.reportTick) {
            guard let latest = store.lastReport else { return }
            report = latest
            if let newest = latest.newestDate { month = newest.yearMonth }
            sheet = .report
        }
        .onChange(of: sheet) { _, new in
            // Das Blatt fährt herunter, bevor die Bestätigung aufsteigt — sonst
            // startet sie dahinter und niemand sieht sie.
            guard new == nil, let pending = pendingFlight else { return }
            pendingFlight = nil
            Task {
                try? await Task.sleep(for: .seconds(0.26))
                flight = pending
            }
        }
        // Seite und Monat laufen gemeinsam: Wischen setzt den Monat, Pfeile und
        // Menü setzen die Seite.
        .onChange(of: page) { _, new in
            if case .month(let m) = new, m != month { month = m }
        }
        .onChange(of: month) { _, new in
            selection = nil
            expanded = nil
            if page != .month(new) { withAnimation(motion) { page = .month(new) } }
        }
        .sensoryFeedback(.success, trigger: store.saveTick)
        .sensoryFeedback(.selection, trigger: page)
    }

    // MARK: - Übersicht

    /// Die Übersicht eines Monats: Kopf, Monat und Summen, die Blasen, die Liste.
    private func overview(for m: YearMonth) -> some View {
        let summary = store.summary(for: m)
        return ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.bottom, 14)
                    figureBlock(m, summary)
                        .padding(.bottom, 12)
                    totals(summary)
                        .padding(.bottom, 14)
                    bubbles(summary)
                        .padding(.bottom, 18)
                    LedgerSection(
                        store: store,
                        ring: summary.ring(listDirection),
                        month: m,
                        neutralTotal: summary.neutralTotal,
                        neutralCount: summary.neutralCount,
                        selection: $selection,
                        expanded: $expanded,
                        onEdit: { sheet = .edit($0) },
                        onRecategorize: { pickerFor = $0 },
                        onLink: { sheet = .link($0) })
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.top, 10)
                // Platz, damit die letzte Zeile nicht unter dem Plus verschwindet.
                .padding(.bottom, 108)
            }
            .scrollIndicators(.hidden)

            LinearGradient(
                colors: [Palette.canvas.opacity(0), Palette.canvas],
                startPoint: .top, endPoint: .bottom)
                .frame(height: 118)
                .frame(maxWidth: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .bottom)

            addButton
        }
    }

    // MARK: - Kopf

    private var header: some View {
        ZStack {
            WordmarkLabel()

            HStack {
                inboxButton
                Spacer()
                Button {
                    withAnimation(motion) { page = .categories }
                } label: {
                    CategoriesGlyph(categories: store.data.categories(for: .expense))
                }
                .buttonStyle(PressableRowStyle())
                .accessibilityLabel("Kategorien")
            }
        }
    }

    /// Der Posteingang, mit Zähler. Ohne Vorschläge bleibt er still und grau.
    private var inboxButton: some View {
        let count = store.proposals.count
        return Button { sheet = .inbox } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: count > 0 ? "tray.full" : "tray")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(count > 0 ? Palette.ink : Palette.faint)
                    .frame(width: 34, height: 34)
                    .glassCapsule(interactive: true)
                if count > 0 {
                    Text(count > 999 ? "999+" : "\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.canvas)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Capsule().fill(Palette.ink))
                        .offset(x: 7, y: -6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(PressableRowStyle())
        .animation(motion, value: count)
        .accessibilityLabel(count > 0 ? "\(count) Vorschläge im Posteingang" : "Posteingang leer")
    }

    // MARK: - Grafik

    private func bubbles(_ summary: MonthSummary) -> some View {
        BubbleField(
            summary: summary,
            onTap: { sheet = .detail($0.category.id) },
            onPendingTap: { sheet = .inbox },
            onNeutralTap: { sheet = .neutral })
            .frame(height: 340)
            .overlay(alignment: .bottom) {
                if summary.isEmpty && !summary.hasPending {
                    Text("Doppeltipp auf die Rückseite, das Plus —\noder einen Export von Trade Republic teilen.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.faint)
                        .padding(.bottom, 120)
                }
            }
    }

    /// Monat und Ergebnis über der Grafik: Der Monat ist die Überschrift der
    /// Seite, das Saldo die Zahl darunter.
    private func figureBlock(_ m: YearMonth, _ summary: MonthSummary) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                monthStep(from: m, -1, "chevron.left")
                monthMenu(m)
                monthStep(from: m, 1, "chevron.right")
            }
            let figure = centerFigure(summary)
            Text(figure.text)
                .font(.system(size: 44, weight: .bold))
                .monospacedDigit()
                .tracking(-1.6)
                .contentTransition(.numericText())
                .foregroundStyle(figure.tone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(figure.caption)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .kerning(1.4)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
    }

    /// Einen Monat vor oder zurück — dasselbe wie Wischen, nur mit Pfeil. Keine Zukunft.
    private func monthStep(from m: YearMonth, _ step: Int, _ symbol: String) -> some View {
        let next = m.advanced(by: step)
        let allowed = next <= YearMonth.current()
        return Button {
            withAnimation(motion) { month = next }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(allowed ? Palette.muted : Palette.faint.opacity(0.4))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!allowed)
        .accessibilityLabel(step < 0 ? "Vormonat" : "Folgemonat")
    }

    private func monthMenu(_ m: YearMonth) -> some View {
        Menu {
            ForEach(selectableMonths, id: \.self) { candidate in
                Button {
                    withAnimation(motion) { month = candidate }
                } label: {
                    if candidate == m {
                        Label(MoneyFormat.month(candidate), systemImage: "checkmark")
                    } else {
                        Text(MoneyFormat.month(candidate))
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(MoneyFormat.month(m))
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 2)
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Monat: \(MoneyFormat.month(m))")
    }

    /// Die letzten zwölf Monate, dazu alles, worin etwas steht.
    private var selectableMonths: [YearMonth] {
        let current = YearMonth.current()
        let recent = (0..<12).map { current.advanced(by: -$0) }
        return Array(store.recordedMonths(including: month).union(recent)).sorted(by: >)
    }

    private struct CenterFigure {
        let caption: String
        let text: String
        let tone: Color
    }

    /// Solange nur eine Seite Zahlen hat, gibt es kein „Übrig" — ein Monat ohne
    /// erfasste Einnahmen ist kein Monat mit Verlust.
    private func centerFigure(_ summary: MonthSummary) -> CenterFigure {
        if summary.isEmpty {
            return CenterFigure(caption: "noch nichts", text: "—", tone: Palette.faint)
        }
        if summary.income.total == 0 {
            let out = summary.expenses.total + summary.invested.total
            return CenterFigure(
                caption: summary.invested.total > 0 ? "ausgegeben und angelegt" : "ausgegeben",
                text: MoneyFormat.hero(out),
                tone: Palette.ink)
        }
        if summary.expenses.total == 0 && summary.invested.total == 0 {
            return CenterFigure(
                caption: "eingenommen",
                text: MoneyFormat.hero(summary.income.total),
                tone: Palette.positive)
        }
        let net = summary.net
        return CenterFigure(
            caption: net < 0 ? "mehr raus als rein" : "übrig",
            text: MoneyFormat.signed(net),
            tone: net < 0 ? Palette.negative : Palette.ink)
    }

    // MARK: - Summen

    private func totals(_ summary: MonthSummary) -> some View {
        HStack(spacing: 0) {
            ForEach(Direction.allCases, id: \.self) { direction in
                TotalSegment(
                    direction: direction,
                    total: summary.ring(direction).total,
                    isActive: listDirection == direction,
                    slide: totalsSlide
                ) {
                    withAnimation(motion) {
                        listDirection = direction
                        if selection?.direction != direction { selection = nil }
                        expanded = nil
                    }
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.card))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: listDirection)
    }

    // MARK: - Erfassen

    private var addButton: some View {
        Button {
            sheet = .quickEntry(.expense)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Palette.canvas)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(Palette.ink)
        .padding(.trailing, Metrics.screenInset)
        .padding(.bottom, 26)
        .accessibilityLabel("Ausgabe erfassen")
        .accessibilityHint("Gedrückt halten für Einnahme, Investition oder Export")
        .contextMenu {
            Button { sheet = .quickEntry(.expense) } label: {
                Label("Ausgabe erfassen", systemImage: "arrow.down.left")
            }
            Button { sheet = .quickEntry(.income) } label: {
                Label("Einnahme erfassen", systemImage: "arrow.up.right")
            }
            Button { sheet = .quickEntry(.invest) } label: {
                Label("Investition erfassen", systemImage: "chart.line.uptrend.xyaxis")
            }
            Divider()
            Button { showsImporter = true } label: {
                Label("Export einlesen (CSV)", systemImage: "square.and.arrow.down")
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: HomeSheet) -> some View {
        switch sheet {
        case .quickEntry(let direction):
            QuickEntrySheet(store: store, direction: direction, editing: nil)
        case .edit(let entry):
            QuickEntrySheet(store: store, direction: entry.direction, editing: entry)
        case .inbox:
            InboxSheet(store: store)
        case .detail(let id):
            if let category = store.data.category(id) {
                CategoryDetailSheet(store: store, category: category, month: month)
            }
        case .link(let entry):
            RefundLinkSheet(store: store, entry: entry)
        case .neutral:
            NeutralSheet(store: store, month: month)
        case .report:
            if let report {
                ImportReportSheet(report: report) {
                    self.sheet = nil
                    Task {
                        try? await Task.sleep(for: .seconds(0.4))
                        self.sheet = .inbox
                    }
                }
            }
        }
    }

    // MARK: - Ablauf

    private struct Flight: Equatable {
        let text: String
        let tint: Color
    }

    /// Startet die Bestätigung, sobald etwas gesichert wurde — egal ob über das Blatt
    /// oder über einen Kurzbefehl im Hintergrund.
    private func takeOff() {
        guard let saved = store.lastSaved else { return }
        // Zum Monat und zur Seite der Buchung — sonst ist sie „nirgends".
        if saved.month != month { month = saved.month }
        if saved.kind != .transfer, listDirection != saved.direction {
            listDirection = saved.direction
            selection = nil
            expanded = nil
        }

        var text = MoneyFormat.signed(saved.signedAmount)
        if saved.kind == .transfer {
            text += " · Umbuchung"
        } else if let category = store.data.category(saved.categoryID) {
            text += " · \(category.symbol) \(category.name)"
        }
        let next = Flight(
            text: text,
            tint: saved.signedAmount > 0 ? Palette.positive : Palette.ink)

        if sheet == nil { flight = next } else { pendingFlight = next }
    }

    private func openRequestedEntry() {
        guard let direction = router.consume() else { return }
        page = .month(month)
        sheet = .quickEntry(direction)
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1)
    }
}

/// Der Knopf zur zweiten Seite: die Farben der eigenen Kategorien als Raster.
private struct CategoriesGlyph: View {
    let categories: [BudgetCategory]

    private var dots: [Color] {
        let tints = categories.prefix(4).map { Palette.tint($0.tint) }
        return tints + Array(repeating: Palette.faint.opacity(0.35), count: 4 - tints.count)
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(7), spacing: 4), count: 2), spacing: 4
        ) {
            ForEach(Array(dots.enumerated()), id: \.offset) { _, color in
                Circle().fill(color).frame(width: 7, height: 7)
            }
        }
        .frame(width: 34, height: 34)
        .glassCapsule(interactive: true)
    }
}

/// Eine der drei Summen. Das Zeichen links ist der Ring selbst im Kleinen.
private struct TotalSegment: View {
    let direction: Direction
    let total: Decimal
    let isActive: Bool
    let slide: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                RingGlyph(direction: direction, isActive: isActive)

                VStack(alignment: .leading, spacing: 0) {
                    Text(direction.plural)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isActive ? Palette.muted : Palette.faint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(MoneyFormat.rounded(total))
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(isActive ? Palette.ink : Palette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Palette.raised)
                        .matchedGeometryEffect(id: "aktiv", in: slide)
                }
            }
        }
        .buttonStyle(PressableRowStyle())
        .accessibilityLabel("\(direction.plural), \(MoneyFormat.amount(total))")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

private struct RingGlyph: View {
    let direction: Direction
    let isActive: Bool

    private var ink: Color { isActive ? Palette.ink : Palette.faint }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(direction == .expense ? ink : Palette.track, lineWidth: 3.5)
                .frame(width: 22, height: 22)
            Circle()
                .strokeBorder(direction == .income ? ink : Palette.track, lineWidth: 2)
                .frame(width: 13, height: 13)
            Circle()
                .fill(direction == .invest ? ink : Palette.track)
                .frame(width: 5, height: 5)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Start") {
    HomeScreen(store: .preview)
}
