// HomeScreen.swift
// budget. — die Seite, auf der alles steht
//
// Zwei Seiten, nicht mehr: die Übersicht und, einen Wisch nach links, die Kategorien.
// Die Übersicht hat drei Ebenen:
//   1. der Monat und das, was übrig bleibt
//   2. die Verteilung — als Blasen (grob) oder als Ringe (genau), antippbar
//   3. die Herkunft — die Liste, aufklappbar
// Dazu, wenn etwas wartet: der Posteingang. Erfasst wird über das Blatt, das der
// Kurzbefehl öffnet — oder über das Plus.

import SwiftUI

enum HomeSheet: Identifiable, Hashable {
    case quickEntry(Direction)
    case edit(Entry)
    case inbox
    case detail(UUID)
    case report

    var id: String {
        switch self {
        case .quickEntry(let direction): return "neu-\(direction.rawValue)"
        case .edit(let entry): return "bearbeiten-\(entry.id)"
        case .inbox: return "posteingang"
        case .detail(let id): return "detail-\(id)"
        case .report: return "bericht"
        }
    }
}

enum OverviewMode: String, CaseIterable {
    case bubbles, rings

    var symbol: String { self == .bubbles ? "circle.hexagongrid.fill" : "circle.circle" }
    var label: String { self == .bubbles ? "Blasen" : "Ringe" }
}

struct HomeScreen: View {
    let store: AppStore

    @State private var page = 0
    @State private var month: YearMonth = .current()
    @State private var selection: RingSelection?
    @State private var listDirection: Direction = .expense
    @State private var expanded: UUID?
    @State private var sheet: HomeSheet?
    @State private var flight: Flight?
    @Namespace private var totalsSlide
    @Namespace private var modeSlide
    @State private var pendingFlight: Flight?
    @AppStorage("overviewMode") private var modeRaw = OverviewMode.bubbles.rawValue
    @State private var report: ImportReport?
    @State private var pickerFor: Entry?

    private let router = QuickEntryRouter.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mode: OverviewMode { OverviewMode(rawValue: modeRaw) ?? .bubbles }
    private var summary: MonthSummary { store.summary(for: month) }

    private var selectedSlice: Slice? {
        guard let selection else { return nil }
        return summary.ring(selection.direction).slices
            .first { $0.category.id == selection.categoryID }
    }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()

            TabView(selection: $page) {
                overview.tag(0)
                CategoriesPage(store: store).tag(1)
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
            CategoryPickerSheet(store: store, direction: entry.direction, current: entry.categoryID) {
                store.correct(entry.id, to: $0)
            }
        }
        .onChange(of: router.token) { openRequestedEntry() }
        .task { openRequestedEntry() }
        .onChange(of: store.saveTick) { takeOff() }
        .onChange(of: store.reportTick) {
            guard let latest = store.lastReport else { return }
            report = latest
            if let newest = latest.newestDate { month = newest.yearMonth }
            page = 0
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
        .onChange(of: selection) { _, new in
            guard let new else { return }
            listDirection = new.direction
            expanded = new.categoryID
        }
        .onChange(of: month) {
            selection = nil
            expanded = nil
        }
        .sensoryFeedback(.selection, trigger: selection) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: store.saveTick)
        .sensoryFeedback(.selection, trigger: modeRaw)
    }

    // MARK: - Übersicht

    private var overview: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.bottom, 6)
                    if store.hasProposals {
                        inboxPill
                            .padding(.bottom, 10)
                    }
                    visual
                        .padding(.bottom, 16)
                    totals
                        .padding(.bottom, 22)
                    LedgerSection(
                        store: store,
                        ring: summary.ring(listDirection),
                        month: month,
                        transferTotal: summary.transferTotal,
                        transferCount: summary.transferCount,
                        selection: $selection,
                        expanded: $expanded,
                        onEdit: { sheet = .edit($0) },
                        onRecategorize: { pickerFor = $0 })
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.top, 10)
                // Platz, damit die letzte Zeile nicht unter dem Plus verschwindet.
                .padding(.bottom, 108)
            }
            .scrollIndicators(.hidden)
            // Der erste und letzte Monat stauchen sich beim Weiterwischen — die Geste
            // sitzt auf der ganzen Seite, nicht nur auf der Grafik.
            .gesture(monthSwipe)

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

    /// Ein Wisch über die Seite blättert den Monat — die Seitenwischgeste des
    /// Pagers bleibt davon unberührt, weil sie deutlich weiter greift.
    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5,
                      abs(value.translation.width) > 90 else { return }
                let step = value.translation.width < 0 ? 1 : -1
                let next = month.advanced(by: step)
                guard next <= YearMonth.current() else { return }
                withAnimation(motion) { month = next }
            }
    }

    // MARK: - Kopf

    private var header: some View {
        ZStack {
            WordmarkLabel()

            HStack {
                modeToggle
                Spacer()
                Button {
                    withAnimation(motion) { page = 1 }
                } label: {
                    CategoriesGlyph(categories: store.data.categories(for: .expense))
                }
                .buttonStyle(PressableRowStyle())
                .accessibilityLabel("Kategorien")
            }
        }
    }

    /// Grob oder genau: Blasen oder Ringe. Ein Glas-Schalter, die aktive Seite
    /// wandert als Fläche.
    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(OverviewMode.allCases, id: \.self) { candidate in
                let isOn = mode == candidate
                Button {
                    withAnimation(motion) { modeRaw = candidate.rawValue }
                } label: {
                    Image(systemName: candidate.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isOn ? Palette.ink : Palette.faint)
                        .frame(width: 32, height: 30)
                        .background {
                            if isOn {
                                Capsule().fill(Palette.raised)
                                    .matchedGeometryEffect(id: "modus", in: modeSlide)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.label)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(2)
        .glassCapsule()
    }

    private var inboxPill: some View {
        Button { sheet = .inbox } label: {
            HStack(spacing: 8) {
                Image(systemName: "tray.full")
                    .font(.footnote.weight(.semibold))
                Text("\(store.proposals.count) Vorschläge warten")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.faint)
            }
            .foregroundStyle(Palette.ink)
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .glassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Grafik

    @ViewBuilder
    private var visual: some View {
        switch mode {
        case .bubbles:
            VStack(spacing: 6) {
                figureBlock
                    .padding(.top, 6)
                BubbleField(
                    summary: summary,
                    onTap: { sheet = .detail($0.category.id) },
                    onPendingTap: { sheet = .inbox })
                    .frame(height: 340)
                if summary.isEmpty && !summary.hasPending {
                    Text("Doppeltipp auf die Rückseite, das Plus —\noder einen Export von Trade Republic teilen.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.faint)
                        .padding(.top, -120)
                }
            }
            .transition(.opacity)
        case .rings:
            FlowRings(summary: summary, selection: $selection) { ringCenter }
                .frame(maxWidth: 310)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .transition(.opacity)
        }
    }

    /// Monat und Ergebnis über den Blasen — in den Ringen sitzt dasselbe in der Mitte.
    private var figureBlock: some View {
        VStack(spacing: 0) {
            monthMenu
            let figure = centerFigure
            Text(figure.text)
                .font(.system(size: 40, weight: .semibold))
                .monospacedDigit()
                .tracking(-1.4)
                .contentTransition(.numericText())
                .foregroundStyle(figure.tone)
                .lineLimit(1)
            Text(figure.caption)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .kerning(1.4)
                .foregroundStyle(Palette.faint)
        }
        .animation(motion, value: month)
    }

    @ViewBuilder
    private var ringCenter: some View {
        VStack(spacing: 2) {
            monthMenu

            if let slice = selectedSlice {
                Text(slice.category.symbol)
                    .font(.system(size: 20))
                    .padding(.top, 2)
                Text(MoneyFormat.hero(slice.total))
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-1)
                    .foregroundStyle(Palette.tint(slice.category.tint))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("\(slice.category.name) · \(MoneyFormat.share(slice.share))")
                    .font(.caption)
                    .foregroundStyle(Palette.faint)
                    .lineLimit(1)
            } else if summary.isEmpty {
                Text("Noch nichts")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 6)
            } else {
                let figure = centerFigure
                Text(figure.text)
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-1.6)
                    .contentTransition(.numericText())
                    .foregroundStyle(figure.tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .padding(.top, 4)
                Text(figure.caption)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(1.4)
                    .foregroundStyle(Palette.faint)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 8)
        .animation(motion, value: selection)
        .accessibilityElement(children: .contain)
    }

    private var monthMenu: some View {
        Menu {
            ForEach(selectableMonths, id: \.self) { candidate in
                Button {
                    withAnimation(motion) { month = candidate }
                } label: {
                    if candidate == month {
                        Label(MoneyFormat.month(candidate), systemImage: "checkmark")
                    } else {
                        Text(MoneyFormat.month(candidate))
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(MoneyFormat.month(month))
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.top, 1)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Monat: \(MoneyFormat.month(month))")
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
    private var centerFigure: CenterFigure {
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

    private var totals: some View {
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
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Palette.canvas)
                .frame(width: 58, height: 58)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(Palette.ink)
        .padding(.trailing, Metrics.screenInset)
        .padding(.bottom, 26)
        .accessibilityLabel("Ausgabe erfassen")
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
        if saved.month != month { month = saved.month }

        let next = Flight(
            text: MoneyFormat.signed(saved.signedAmount),
            tint: saved.direction == .income ? Palette.positive : Palette.ink)

        if sheet == nil { flight = next } else { pendingFlight = next }
    }

    private func openRequestedEntry() {
        guard let direction = router.consume() else { return }
        page = 0
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
                        .font(.system(size: 10))
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
