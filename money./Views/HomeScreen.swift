// HomeScreen.swift
// budget. — die einzige Seite
//
// Es gibt keine zweite. Alles, was die App weiß, steht hier oder ist von hier aus
// einen Fingertipp entfernt: die zwei Ringe, die Summen, jede Kategorie, und unter
// jeder Kategorie jede einzelne Buchung.
//
// Die Seite hat drei Ebenen, und mehr soll sie nie bekommen:
//   1. der Monat        — oben, blätterbar
//   2. die Verteilung   — die Ringe, antippbar
//   3. die Herkunft     — die Liste, aufklappbar
// Erfasst wird über das Blatt, das der Kurzbefehl öffnet — oder über das Plus.

import SwiftUI

enum HomeSheet: Identifiable, Hashable {
    case quickEntry(Direction)
    case edit(Entry)
    case settings

    var id: String {
        switch self {
        case .quickEntry(let direction): return "neu-\(direction.rawValue)"
        case .edit(let entry): return "bearbeiten-\(entry.id)"
        case .settings: return "einstellungen"
        }
    }
}

struct HomeScreen: View {
    let store: AppStore

    @State private var month: YearMonth = .current()
    @State private var selection: RingSelection?
    @State private var listDirection: Direction = .expense
    @State private var expanded: UUID?
    @State private var sheet: HomeSheet?

    private let router = QuickEntryRouter.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summary: MonthSummary { store.summary(for: month) }

    private var selectedSlice: Slice? {
        guard let selection else { return nil }
        return summary.ring(selection.direction).slices
            .first { $0.category.id == selection.categoryID }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Palette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    monthBar
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
                .padding(.top, 6)
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
        .tint(Palette.accent)
        .sheet(item: $sheet, content: sheetContent)
        .onChange(of: router.token) { openRequestedEntry() }
        .task { openRequestedEntry() }
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
        .sensoryFeedback(.success, trigger: store.revision)
    }

    // MARK: - Kopf

    private var header: some View {
        ZStack {
            WordmarkLabel()

            HStack {
                CircleIconButton(systemImage: "slider.horizontal.3") { sheet = .settings }
                    .accessibilityLabel("Kategorien und Einrichtung")
                Spacer()
                // Gegengewicht, damit die Wortmarke wirklich mittig steht.
                Color.clear.frame(width: 38, height: 38)
            }
        }
    }

    private var monthBar: some View {
        HStack(spacing: 4) {
            stepButton(-1, symbol: "chevron.left", label: "Vorheriger Monat")

            Text(MoneyFormat.month(month))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 132)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            stepButton(1, symbol: "chevron.right", label: "Nächster Monat")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 5)
        .background(Capsule().fill(Palette.raised))
        // Die Kapsel bleibt mittig; der Rücksprung in den laufenden Monat legt sich
        // rechts daneben, statt die Mitte zu verschieben.
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            if month != .current() {
                Button("Heute") { step(to: .current()) }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .buttonStyle(.plain)
                    .transition(.opacity)
            }
        }
        .animation(motion, value: month)
    }

    private func stepButton(_ offset: Int, symbol: String, label: String) -> some View {
        Button { step(to: month.advanced(by: offset)) } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.faint)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Ringe

    private var rings: some View {
        FlowRings(summary: summary, selection: $selection) { ringCenter }
            // Gedeckelt, damit die Grafik auf großen Geräten nicht die ganze Seite
            // einnimmt — unter den Ringen soll die erste Kategorie sichtbar bleiben.
            .frame(maxWidth: 310)
            .frame(maxWidth: .infinity)
            .gesture(
                // Wischen blättert den Monat weiter. Der Mindestweg ist großzügig,
                // damit das vertikale Scrollen die Geste nicht verliert.
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.6
                        else { return }
                        step(to: month.advanced(by: value.translation.width < 0 ? 1 : -1))
                    })
    }

    @ViewBuilder
    private var ringCenter: some View {
        VStack(spacing: 5) {
            if let slice = selectedSlice {
                Text(slice.category.symbol)
                    .font(.system(size: 22))
                Text(slice.category.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                Text(MoneyFormat.hero(slice.total))
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-1)
                    .foregroundStyle(Palette.tint(slice.category.tint))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("\(MoneyFormat.share(slice.share)) der \(slice.category.direction.plural)")
                    .font(.caption)
                    .foregroundStyle(Palette.faint)
            } else if summary.isEmpty {
                Text("Noch nichts")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text("Doppeltipp auf die Rückseite\noder unten das Plus.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.faint)
            } else {
                let figure = centerFigure
                Text(figure.caption)
                    .font(.caption.weight(.medium))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundStyle(Palette.muted)
                Text(figure.text)
                    .font(.system(size: 46, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-1.4)
                    .contentTransition(.numericText())
                    .foregroundStyle(figure.tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(.horizontal, 8)
        .animation(motion, value: selection)
        .accessibilityElement(children: .combine)
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
                caption: "Ausgaben",
                text: MoneyFormat.hero(summary.expenses.total),
                tone: Palette.ink)
        }
        if summary.expenses.total == 0 {
            return CenterFigure(
                caption: "Einnahmen",
                text: MoneyFormat.hero(summary.income.total),
                tone: Palette.positive)
        }
        let net = summary.net
        return CenterFigure(
            caption: net < 0 ? "Zu viel ausgegeben" : "Übrig",
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
        case .settings:
            SettingsSheet(store: store)
        }
    }

    // MARK: - Ablauf

    /// Holt ab, was der Kurzbefehl hinterlegt hat. Wird zweimal versucht — beim
    /// Erscheinen (Kaltstart: der Kurzbefehl war schneller als die Oberfläche) und
    /// bei jeder weiteren Anforderung (App lief schon).
    private func openRequestedEntry() {
        guard let direction = router.consume() else { return }
        sheet = .quickEntry(direction)
    }

    private func step(to target: YearMonth) {
        withAnimation(motion) { month = target }
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1)
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
                .strokeBorder(
                    direction == .expense ? ink : Palette.track, lineWidth: 3.5)
                .frame(width: 22, height: 22)
            Circle()
                .strokeBorder(
                    direction == .income ? ink : Palette.track, lineWidth: 2)
                .frame(width: 11, height: 11)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Start") {
    HomeScreen(store: .preview)
}
