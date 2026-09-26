// RefundLinkSheet.swift
// budget. — einen Ausgleich zuordnen
//
// „Ich habe 35 € für Unterwegs ausgegeben und 35 € von meinem Vater bekommen."
// Das Geld ist keine Einnahme, es macht die Ausgabe kleiner. Hier wird die
// Verbindung von Hand gezogen: zu einer Einnahme die Ausgabe, zu einer Ausgabe
// der Eingang. Gleiche Beträge stehen oben.

import SwiftUI

struct RefundLinkSheet: View {
    let store: AppStore
    let entry: Entry

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var candidates: [Entry] { store.refundCandidates(for: entry) }
    private var isInbound: Bool { entry.isInflow }

    /// Suche über Name, Notiz, Kategorie und Betrag — „DB" findet die Bahn.
    private var matching: [Entry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return candidates }
        return candidates.filter { item in
            let category = store.data.category(item.categoryID)?.name ?? ""
            let haystack = [item.title, item.note, item.merchant ?? "", category,
                            MoneyFormat.amount(item.amount), MoneyFormat.plain(item.amount)]
                .joined(separator: " ").lowercased()
            return haystack.contains(needle)
        }
    }
    private var exact: [Entry] { matching.filter { $0.amount.roughlyEquals(entry.amount) } }
    private var recent: [Entry] {
        matching.filter { !$0.amount.roughlyEquals(entry.amount) && abs(SuggestionEngine.daysBetween($0.date, entry.date)) <= 90 }
    }
    private var older: [Entry] {
        matching.filter { !$0.amount.roughlyEquals(entry.amount) && abs(SuggestionEngine.daysBetween($0.date, entry.date)) > 90 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(entry, highlighted: true)
                        .listRowBackground(Palette.card)
                } header: {
                    Text(isInbound ? "Dieser Eingang gleicht aus …" : "Diese Ausgabe wird ausgeglichen durch …")
                }
                if matching.isEmpty {
                    Text(query.isEmpty
                         ? (isInbound ? "Keine Ausgaben vorhanden." : "Keine Eingänge vorhanden.")
                         : "Nichts gefunden für \u{201E}\(query)\u{201C}.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .listRowBackground(Palette.card)
                }
                if !exact.isEmpty {
                    Section("Passender Betrag") {
                        ForEach(exact) { candidate in pick(candidate) }
                    }
                }
                if !recent.isEmpty {
                    Section("Davor und danach, 90 Tage") {
                        ForEach(recent) { candidate in pick(candidate) }
                    }
                }
                if !older.isEmpty {
                    Section("Weiter entfernt") {
                        ForEach(older.prefix(query.isEmpty ? 60 : 300)) { candidate in pick(candidate) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, Kategorie oder Betrag")
            .navigationTitle("Ausgleich")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }.foregroundStyle(Palette.muted)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .tint(Palette.accent)
        .presentationDetents([.large])
    }

    private func pick(_ candidate: Entry) -> some View {
        Button {
            if isInbound {
                store.linkRefund(entry.id, to: candidate.id)
            } else {
                store.linkRefund(candidate.id, to: entry.id)
            }
            dismiss()
        } label: {
            row(candidate, highlighted: false)
        }
        .listRowBackground(Palette.card)
    }

    /// Wo die Buchung gerade steht — damit klar ist, was ein Tipp verändert.
    private func whereabouts(_ item: Entry) -> String {
        if item.kind == .transfer { return "Neutral" }
        if item.kind == .refund, let id = item.refundOf, let original = store.entry(id) {
            return "Ausgleich für \(original.title.isEmpty ? (store.data.category(original.categoryID)?.name ?? "") : original.title)"
        }
        if item.status == .proposed { return "offen" }
        return store.data.category(item.categoryID)?.name ?? ""
    }

    private func row(_ item: Entry, highlighted: Bool) -> some View {
        HStack(spacing: 12) {
            if item.kind == .transfer {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.faint)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Palette.raised))
            } else if let category = store.data.category(item.categoryID) {
                CategoryBadge(category: category, side: 32)
            } else {
                Circle().fill(Palette.raised).frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title.isEmpty ? (store.data.category(item.categoryID)?.name ?? "Ohne Namen") : item.title)
                    .font(.subheadline.weight(highlighted ? .semibold : .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(highlighted ? MoneyFormat.dayLong(item.date) : "\(MoneyFormat.dayLong(item.date)) · \(whereabouts(item))")
                    .font(.caption)
                    .foregroundStyle(Palette.faint)
                    .lineLimit(1)
            }
            Spacer()
            Text(MoneyFormat.signed(item.signedAmount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(item.signedAmount > 0 ? Palette.positive : Palette.ink)
        }
    }
}
