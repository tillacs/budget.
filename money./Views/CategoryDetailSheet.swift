// CategoryDetailSheet.swift
// budget. — eine Kategorie von Nahem
//
// Von der Blase aufgeklappt: oben die Zahl, darunter die letzten sechs Monate als
// schlichte Balken, dann die Händler nach Summe, aufklappbar zu den einzelnen
// Buchungen. Jede Buchung lässt sich hier umkategorisieren — und die App lernt.

import SwiftUI

struct CategoryDetailSheet: View {
    let store: AppStore
    let category: BudgetCategory
    let initialMonth: YearMonth

    init(store: AppStore, category: BudgetCategory, month: YearMonth) {
        self.store = store
        self.category = category
        self.initialMonth = month
        _month = State(initialValue: month)
        _anchor = State(initialValue: month)
    }

    /// Der Monat, den die Ansicht zeigt — per Tipp auf einen Balken wechselbar.
    @State private var month: YearMonth
    /// Der rechte Rand des Balkenfensters; die Pfeile verschieben es.
    @State private var anchor: YearMonth

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: String?
    @State private var pickerFor: Entry?
    @State private var linkFor: Entry?

    private var tint: Color { Palette.tint(category.tint) }
    private var entries: [Entry] { store.entries(of: category.id, in: month) }
    private var total: Decimal { entries.reduce(0) { $0 + net($1) } }

    /// Nach Ausgleichen: Was die Buchung wirklich gekostet hat.
    private func net(_ entry: Entry) -> Decimal {
        entry.kind == .refund ? -entry.amount : store.netAmount(of: entry)
    }

    private struct MerchantGroup: Identifiable {
        let id: String
        let name: String
        let entries: [Entry]
        var total: Decimal = 0
    }

    private var groups: [MerchantGroup] {
        var order: [String] = []
        var buckets: [String: [Entry]] = [:]
        for entry in entries {
            let key = entry.merchant.flatMap(MerchantKey.normalized)
                ?? (entry.note.isEmpty ? "—" : entry.note.uppercased())
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }
        return order.map { key in
            let list = buckets[key] ?? []
            let name = list.first.map { $0.title.isEmpty ? "Ohne Namen" : $0.title } ?? key
            return MerchantGroup(id: key, name: name, entries: list, total: list.reduce(0) { $0 + net($1) })
        }
        .sorted { $0.total > $1.total }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    history
                    merchants
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.bottom, 30)
            }
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }.fontWeight(.semibold).foregroundStyle(Palette.ink)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .tint(Palette.accent)
        .presentationDetents([.large])
        .sheet(item: $pickerFor) { entry in
            CategoryPickerSheet(
                store: store, direction: entry.direction, current: entry.categoryID,
                allowed: entry.compatibleDirections
            ) {
                store.correct(entry.id, to: $0)
            }
        }
        .sheet(item: $linkFor) { entry in
            RefundLinkSheet(store: store, entry: entry)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.95), tint.opacity(0.7)],
                                         center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 80))
                    .shadow(color: tint.opacity(0.3), radius: 18, y: 8)
                Text(category.symbol).font(.system(size: 44))
            }
            .frame(width: 104, height: 104)
            .padding(.top, 6)

            Text(MoneyFormat.amount(total))
                .font(.system(size: 40, weight: .semibold))
                .monospacedDigit()
                .tracking(-1.2)
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            Text("\(category.name) · \(MoneyFormat.month(month))")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
        }
    }

    /// Sechs Monate als Balken, jeder antippbar: Die Ansicht springt in diesen
    /// Monat. Der Wert steht am höchsten und am gewählten Balken.
    private var history: some View {
        let months = (0..<6).reversed().map { anchor.advanced(by: -$0) }
        let values = months.map { m -> Decimal in
            store.summary(for: m).ring(category.direction).slices
                .first { $0.category.id == category.id }?.total ?? 0
        }
        let peak = values.max() ?? 0
        let canGoForward = anchor < YearMonth.current()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                windowStep(-6, "chevron.left", enabled: true)
                ForEach(Array(zip(months, values)), id: \.0) { m, value in
                    Button {
                        withAnimation(motion) { month = m }
                    } label: {
                        VStack(spacing: 5) {
                            if (value == peak && peak > 0) || m == month {
                                Text(MoneyFormat.hero(value))
                                    .font(.system(size: 10, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(m == month ? Palette.ink : Palette.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(m == month ? tint : tint.opacity(0.3))
                                .frame(height: peak > 0 ? max(4, 70 * (value / peak).doubleValue) : 4)
                            Text(shortMonth(m))
                                .font(.system(size: 10, weight: m == month ? .semibold : .regular))
                                .foregroundStyle(m == month ? Palette.ink : Palette.faint)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableRowStyle())
                    .accessibilityLabel("\(MoneyFormat.month(m)): \(MoneyFormat.amount(value))")
                    .accessibilityAddTraits(m == month ? [.isSelected] : [])
                }
                windowStep(6, "chevron.right", enabled: canGoForward)
            }
            .frame(height: 110, alignment: .bottom)
        }
        .sensoryFeedback(.selection, trigger: month)
        .padding(Metrics.cardPadding)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private var merchants: some View {
        CardStack {
            if groups.isEmpty {
                Text("Keine Buchungen in diesem Monat")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            }
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 { RowDivider() }
                Button {
                    withAnimation(motion) { expanded = expanded == group.id ? nil : group.id }
                } label: {
                    HStack(spacing: 10) {
                        Text(group.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        CountChip(count: group.entries.count)
                        Spacer(minLength: 6)
                        Text(MoneyFormat.amount(group.total))
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                            .fixedSize()
                            .layoutPriority(2)
                    }
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableRowStyle())
                if expanded == group.id {
                    VStack(spacing: 0) {
                        ForEach(group.entries) { entry in entryRow(entry) }
                    }
                    .padding(.bottom, 6)
                    .background(tint.opacity(0.05))
                    .transition(.opacity)
                }
            }
        }
        .animation(motion, value: expanded)
    }

    private func entryRow(_ entry: Entry) -> some View {
        let refunds = store.refunds(of: entry.id)
        return HStack(spacing: 10) {
            Capsule().fill(tint).frame(width: 3, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(MoneyFormat.day(entry.date))
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                    EntryMarks(entry: entry)
                }
                ForEach(refunds) { refund in
                    Text("−\(MoneyFormat.amount(refund.amount)) Ausgleich\(refund.title.isEmpty ? "" : " von \(refund.title)"), \(MoneyFormat.day(refund.date))")
                        .font(.caption2)
                        .foregroundStyle(Palette.positive)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 0) {
                Text((entry.kind == .refund ? "+" : "") + MoneyFormat.amount(refunds.isEmpty ? entry.amount : store.netAmount(of: entry)))
                    .font(.subheadline.weight(refunds.isEmpty ? .regular : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(entry.kind == .refund ? Palette.positive : (refunds.isEmpty ? Palette.muted : Palette.ink))
                if !refunds.isEmpty {
                    Text(MoneyFormat.amount(entry.amount))
                        .font(.caption2)
                        .monospacedDigit()
                        .strikethrough()
                        .foregroundStyle(Palette.faint)
                }
            }
            Menu {
                Button { pickerFor = entry } label: { Label("Kategorie ändern", systemImage: "tag") }
                if entry.kind == .refund, entry.refundOf != nil {
                    Button { store.unlinkRefund(entry.id) } label: {
                        Label("Ausgleich lösen", systemImage: "arrow.uturn.forward")
                    }
                } else if entry.kind == .flow {
                    Button { linkFor = entry } label: {
                        Label(entry.direction == .income ? "Als Ausgleich zuordnen …" : "Ausgleich zuordnen …",
                              systemImage: "arrow.uturn.backward")
                    }
                }
                Button { store.reject(entry.id, as: .transfer) } label: {
                    Label("Nach Neutral verschieben", systemImage: "arrow.left.arrow.right")
                }
                Button(role: .destructive) {
                    withAnimation(motion) { store.deleteEntry(entry.id) }
                } label: { Label("Löschen", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.faint)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
        }
        .padding(.leading, Metrics.cardPadding + 4)
        .padding(.trailing, Metrics.cardPadding - 6)
        .padding(.vertical, 6)
    }

    /// Das Fenster um ein halbes Jahr verschieben — nicht in die Zukunft.
    private func windowStep(_ step: Int, _ symbol: String, enabled: Bool) -> some View {
        Button {
            withAnimation(motion) {
                anchor = min(anchor.advanced(by: step), YearMonth.current())
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Palette.faint : Palette.faint.opacity(0.3))
                .frame(width: 18, height: 60)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(step < 0 ? "Frühere Monate" : "Spätere Monate")
    }

    private func shortMonth(_ m: YearMonth) -> String {
        var components = DateComponents()
        components.year = m.year; components.month = m.month; components.day = 1
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return "\(m.month)" }
        return date.formatted(.dateTime.month(.abbreviated))
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1)
    }
}
