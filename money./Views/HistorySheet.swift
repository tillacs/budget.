// HistorySheet.swift
// budget. — der Verlauf: alles, chronologisch, wie ein Kontoauszug
//
// Jede Buchung eines Monats in der Reihenfolge, in der das Geld geflossen ist:
// Ausgaben, Einnahmen, Investitionen, Umbuchungen, Ausgleiche, offene Vorschläge.
// Daneben steht, wo sie gelandet ist. Suchen geht über alle Monate.

import SwiftUI

struct HistorySheet: View {
    let store: AppStore
    let initialMonth: YearMonth

    init(store: AppStore, month: YearMonth) {
        self.store = store
        self.initialMonth = month
        _month = State(initialValue: month)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var month: YearMonth
    @State private var query = ""
    @State private var pickerFor: Entry?
    @State private var linkFor: Entry?

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Ohne Suche der Monat, mit Suche alles — neueste zuerst.
    private var entries: [Entry] {
        let pool = searching ? store.data.entries : store.data.entries.filter { $0.month == month }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = needle.isEmpty ? pool : pool.filter { item in
            let category = store.data.category(item.categoryID)?.name ?? ""
            return [item.title, item.note, item.merchant ?? "", category,
                    MoneyFormat.amount(item.amount), MoneyFormat.plain(item.amount)]
                .joined(separator: " ").lowercased().contains(needle)
        }
        return matching.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }

    private struct Day: Identifiable {
        let date: CalendarDate
        let entries: [Entry]
        var id: CalendarDate { date }
    }

    private var days: [Day] {
        var order: [CalendarDate] = []
        var buckets: [CalendarDate: [Entry]] = [:]
        for entry in entries {
            if buckets[entry.date] == nil { order.append(entry.date) }
            buckets[entry.date, default: []].append(entry)
        }
        return order.map { Day(date: $0, entries: buckets[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !searching { monthHeader }
                if days.isEmpty {
                    Text(searching ? "Nichts gefunden für \u{201E}\(query)\u{201C}." : "Keine Buchungen in diesem Monat.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .listRowBackground(Palette.card)
                }
                ForEach(days) { day in
                    Section {
                        ForEach(day.entries) { entry in
                            row(entry)
                                .listRowBackground(Palette.card)
                        }
                    } header: {
                        Text(searching ? MoneyFormat.dayLong(day.date) : MoneyFormat.day(day.date))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Alle Monate durchsuchen")
            .navigationTitle("Verlauf")
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
            ) { store.correct(entry.id, to: $0) }
        }
        .sheet(item: $linkFor) { entry in
            RefundLinkSheet(store: store, entry: entry)
        }
        .sensoryFeedback(.selection, trigger: month)
    }

    /// Monat mit Pfeilen und den Summen des Monats — der Kopf des Auszugs.
    private var monthHeader: some View {
        let summary = store.summary(for: month)
        let canForward = month < YearMonth.current()
        return Section {
            VStack(spacing: 8) {
                HStack {
                    Button { withAnimation(motion) { month = month.advanced(by: -1) } } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Vormonat")
                    Spacer()
                    Text(MoneyFormat.month(month))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    Spacer()
                    Button { withAnimation(motion) { month = month.advanced(by: 1) } } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(canForward ? Palette.muted : Palette.faint.opacity(0.4))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canForward)
                    .accessibilityLabel("Folgemonat")
                }
                HStack(spacing: 14) {
                    stat("Ausgaben", summary.expenses.total, Palette.ink)
                    stat("Einnahmen", summary.income.total, Palette.positive)
                    stat("Investiert", summary.invested.total, Palette.ink)
                    stat("Neutral", summary.neutralTotal, Palette.faint)
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func stat(_ label: String, _ value: Decimal, _ tone: Color) -> some View {
        VStack(spacing: 1) {
            Text(MoneyFormat.rounded(value))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity)
    }

    /// Eine Zeile: Name, wohin sie gehört, der Betrag mit echtem Vorzeichen.
    private func row(_ entry: Entry) -> some View {
        let category = store.data.category(entry.categoryID)
        let original = entry.refundOf.flatMap { store.entry($0) }
        return HStack(spacing: 12) {
            marker(entry, category)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? (category?.name ?? "Ohne Namen") : entry.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(destination(entry, category, original))
                        .lineLimit(1)
                    EntryMarks(entry: entry)
                }
                .font(.caption)
                .foregroundStyle(entry.status == .proposed ? Palette.accent : Palette.faint)
            }
            Spacer(minLength: 6)
            Text(MoneyFormat.signed(entry.signedAmount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(entry.kind == .transfer ? Palette.muted
                                 : (entry.signedAmount > 0 ? Palette.positive : Palette.ink))
                .fixedSize()
            menu(entry)
        }
        .opacity(entry.kind == .transfer ? 0.75 : 1)
    }

    /// Das Zeichen links: die Kategorie, ein Fragezeichen für Offenes, das
    /// Neutral-Symbol für Umbuchungen.
    @ViewBuilder
    private func marker(_ entry: Entry, _ category: BudgetCategory?) -> some View {
        if entry.kind == .transfer {
            Image(systemName: "arrow.left.arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.faint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Palette.raised))
        } else if entry.status == .proposed {
            Image(systemName: "questionmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.raised))
        } else if let category {
            CategoryBadge(category: category, side: 32)
        } else {
            Circle().fill(Palette.raised).frame(width: 32, height: 32)
        }
    }

    private func destination(_ entry: Entry, _ category: BudgetCategory?, _ original: Entry?) -> String {
        if entry.kind == .transfer { return "Neutral · Umbuchung" }
        if entry.kind == .refund {
            if let original {
                return "Ausgleich für \(original.title.isEmpty ? (category?.name ?? "") : original.title)"
            }
            return "Erstattung · \(category?.name ?? "")"
        }
        if entry.status == .proposed {
            return "offen" + (entry.suggestion?.isGuess == false ? " · Vorschlag: \(category?.name ?? "")" : "")
        }
        return category?.name ?? "Ohne Kategorie"
    }

    private func menu(_ entry: Entry) -> some View {
        Menu {
            if entry.kind != .transfer {
                Button { pickerFor = entry } label: { Label("Kategorie ändern", systemImage: "tag") }
            }
            if entry.kind == .refund, entry.refundOf != nil {
                Button { store.unlinkRefund(entry.id) } label: {
                    Label("Ausgleich lösen", systemImage: "arrow.uturn.forward")
                }
            } else if entry.kind != .refund, entry.isInflow {
                Button { linkFor = entry } label: {
                    Label("Als Ausgleich einer Ausgabe zuordnen …", systemImage: "arrow.uturn.backward")
                }
            } else if entry.kind == .flow {
                Button { linkFor = entry } label: {
                    Label("Ausgleich zuordnen …", systemImage: "arrow.uturn.backward")
                }
                ForEach(store.refunds(of: entry.id)) { refund in
                    Button { store.unlinkRefund(refund.id) } label: {
                        Label("Ausgleich entfernen: \(MoneyFormat.amount(refund.amount))", systemImage: "xmark.circle")
                    }
                }
            }
            if entry.kind == .transfer {
                Button { store.restoreFromNeutral(entry.id) } label: {
                    Label("Doch zählen — in den Posteingang", systemImage: "tray")
                }
            } else {
                Button { store.reject(entry.id, as: .transfer) } label: {
                    Label("Nach Neutral verschieben", systemImage: "arrow.left.arrow.right")
                }
            }
            Button(role: .destructive) { store.deleteEntry(entry.id) } label: {
                Label("Löschen", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.faint)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.1)
    }
}
