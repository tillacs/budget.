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

    private var candidates: [Entry] { store.refundCandidates(for: entry) }
    private var exact: [Entry] { candidates.filter { $0.amount == entry.amount } }
    private var others: [Entry] { candidates.filter { $0.amount != entry.amount } }
    private var isInbound: Bool { entry.direction == .income }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(entry, highlighted: true)
                        .listRowBackground(Palette.card)
                } header: {
                    Text(isInbound ? "Dieser Eingang gleicht aus …" : "Diese Ausgabe wird ausgeglichen durch …")
                }
                if candidates.isEmpty {
                    Text(isInbound ? "Keine Ausgabe in den 90 Tagen davor."
                                   : "Kein Eingang in den 90 Tagen danach.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .listRowBackground(Palette.card)
                }
                if !exact.isEmpty {
                    Section("Gleicher Betrag") {
                        ForEach(exact) { candidate in pick(candidate) }
                    }
                }
                if !others.isEmpty {
                    Section("Andere Beträge") {
                        ForEach(others) { candidate in pick(candidate) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
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
        .presentationDetents([.medium, .large])
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

    private func row(_ item: Entry, highlighted: Bool) -> some View {
        HStack(spacing: 12) {
            if let category = store.data.category(item.categoryID) {
                CategoryBadge(category: category, side: 32)
            } else {
                Circle().fill(Palette.raised).frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title.isEmpty ? (store.data.category(item.categoryID)?.name ?? "Ohne Namen") : item.title)
                    .font(.subheadline.weight(highlighted ? .semibold : .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(MoneyFormat.day(item.date))
                    .font(.caption)
                    .foregroundStyle(Palette.faint)
            }
            Spacer()
            Text(MoneyFormat.signed(item.signedAmount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(item.signedAmount > 0 ? Palette.positive : Palette.ink)
        }
    }
}
