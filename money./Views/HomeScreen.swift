// HomeScreen.swift
// budget. — die Seite, auf der alles steht
//
// Zwei Seiten, nicht mehr: die Übersicht und, einen Wisch nach links, die Kategorien.
// Die Übersicht hat drei Ebenen, und mehr soll sie nie bekommen:
//   1. der Monat        — in der Ringmitte, antippbar
//   2. die Verteilung   — die Ringe, antippbar
//   3. die Herkunft     — die Liste, aufklappbar
// Erfasst wird über das Blatt, das der Kurzbefehl öffnet — oder über das Plus.

import SwiftUI

enum HomeSheet: Identifiable, Hashable {
    case quickEntry(Direction)
    case edit(Entry)

    var id: String {
        switch self {
        case .quickEntry(let direction): return "neu-\(direction.rawValue)"
        case .edit(let entry): return "bearbeiten-\(entry.id)"
        }
    }
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
    @State private var pendingFlight: Flight?

    private let router = QuickEntryRouter.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .onChange(of: router.token) { openRequestedEntry() }
        .task { openRequestedEntry() }
        .onChange(of: store.saveTick) { takeOff() }
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
    }

    // MARK: - Übersicht

    private var overview: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    rings
                    totals
                    LedgerSection(
                        store: store,
                        ring: summary.ring(listDirection),
                        month: month,
                        selection: $selection,
                        expanded: $expanded,
                        onEdit: { sheet = .edit($0) })
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.top, 10)
                // Platz, damit die letzte Zeile nicht unter dem Plus verschwindet.
                .padding(.bottom, 108)
            }
            .scrollIndicators(.hidden)

            // Weicher Boden, damit die Liste unter dem Plus verschwindet und nicht
            // dahinter hängen bleibt.
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
                // Gegengewicht, damit die Wortmarke wirklich mittig steht.
                Color.clear.frame(width: 34, height: 34)
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

    // MARK: - Ringe

    private var rings: some View {
        FlowRings(summary: summary, selection: $selection) { ringCenter }
            // Gedeckelt, damit die Grafik auf großen Geräten nicht die ganze Seite
            // einnimmt — unter den Ringen soll die erste Kategorie sichtbar bleiben.
            .frame(maxWidth: 310)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var ringCenter: some View {
        VStack(spacing: 4) {
            monthMenu

            if let slice = selectedSlice {
                Text(slice.category.symbol)
                    .font(.system(size: 20))
                    .padding(.top, 2)
                Text(MoneyFormat.hero(slice.total))
                    .font(.system(size: 38, weight: .semibold))
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
                Text("Doppeltipp auf die Rückseite\noder unten das Plus.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.faint)
            } else {
                let figure = centerFigure
                Text(figure.text)
                    .font(.system(size: 44, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-1.4)
                    .contentTransition(.numericText())
                    .foregroundStyle(figure.tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 2)
                Text(figure.caption)
                    .font(.caption)
                    .foregroundStyle(Palette.faint)
            }
        }
        .padding(.horizontal, 8)
        .animation(motion, value: selection)
        .accessibilityElement(children: .contain)
    }

    /// Der Monat sitzt in der Ringmitte, nicht über der Seite: Er gehört zu den
    /// Zahlen, die er begrenzt, und oben wäre er nur eine zweite Leiste.
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
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Capsule().fill(Palette.raised.opacity(0.7)))
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
    /// erfasste Einnahmen ist kein Monat mit Verlust. Dann steht die Summe da, die
    /// es wirklich gibt.
    private var centerFigure: CenterFigure {
        if summary.income.total == 0 {
            return CenterFigure(
                caption: "ausgegeben",
                text: MoneyFormat.hero(summary.expenses.total),
                tone: Palette.ink)
        }
        if summary.expenses.total == 0 {
            return CenterFigure(
                caption: "eingenommen",
                text: MoneyFormat.hero(summary.income.total),
                tone: Palette.positive)
        }
        let net = summary.net
        return CenterFigure(
            caption: net < 0 ? "zu viel ausgegeben" : "übrig",
            text: MoneyFormat.signed(net),
            tone: net < 0 ? Palette.negative : Palette.ink)
    }

    // MARK: - Summen

    private var totals: some View {
        HStack(spacing: 10) {
            ForEach(Direction.allCases, id: \.self) { direction in
                TotalPill(
                    direction: direction,
                    total: summary.ring(direction).total,
                    isActive: listDirection == direction
                ) {
                    withAnimation(motion) {
                        listDirection = direction
                        if selection?.direction != direction { selection = nil }
                        expanded = nil
                    }
                }
            }
        }
    }

    // MARK: - Erfassen

    private var addButton: some View {
        Button {
            sheet = .quickEntry(.expense)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Palette.canvas)
                .frame(width: 62, height: 62)
                .background(Circle().fill(Palette.ink))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        }
        .buttonStyle(PressableRowStyle())
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
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: HomeSheet) -> some View {
        switch sheet {
        case .quickEntry(let direction):
            QuickEntrySheet(store: store, direction: direction, editing: nil)
        case .edit(let entry):
            QuickEntrySheet(store: store, direction: entry.direction, editing: entry)
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
        // Der Monat der Buchung, damit man sie auch sieht, wenn man gerade woanders steht.
        if saved.month != month { month = saved.month }

        let next = Flight(
            text: MoneyFormat.signed(saved.signedAmount),
            tint: saved.direction == .income ? Palette.positive : Palette.ink)

        // Kam die Buchung aus dem Blatt, wartet die Bestätigung, bis es zu ist.
        // Kam sie aus einem Kurzbefehl im Hintergrund, steigt sie sofort auf.
        if sheet == nil { flight = next } else { pendingFlight = next }
    }

    /// Holt ab, was der Kurzbefehl hinterlegt hat. Wird zweimal versucht — beim
    /// Erscheinen (Kaltstart: der Kurzbefehl war schneller als die Oberfläche) und
    /// bei jeder weiteren Anforderung (App lief schon).
    private func openRequestedEntry() {
        guard let direction = router.consume() else { return }
        page = 0
        sheet = .quickEntry(direction)
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1)
    }
}

/// Der Knopf zur zweiten Seite: die Farben der eigenen Kategorien als Raster. Ein
/// Zahnrad wäre eine Einstellung — hier liegen aber die Kategorien, und die haben
/// eine Farbe, an der man sie wiedererkennt.
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
        .background(Circle().fill(Palette.raised))
    }
}

/// Eine der beiden Summen unter den Ringen. Das Zeichen links ist der Ring selbst
/// im Kleinen: außen dick für Ausgaben, innen dünn für Einnahmen — damit klar ist,
/// welche Summe zu welchem Ring gehört, ohne ein Wort darüber zu verlieren.
private struct TotalPill: View {
    let direction: Direction
    let total: Decimal
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RingGlyph(direction: direction, isActive: isActive)

                VStack(alignment: .leading, spacing: 1) {
                    Text(direction.plural)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                    Text(MoneyFormat.hero(total))
                        .font(.system(size: 19, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? Palette.card : Palette.card.opacity(0.55)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isActive ? Palette.ink.opacity(0.35) : Palette.hairline,
                                  lineWidth: isActive ? 1.5 : 1))
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
                .frame(width: 11, height: 11)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Start") {
    HomeScreen(store: .preview)
}
