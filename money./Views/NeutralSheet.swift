// NeutralSheet.swift
// budget. — der neutrale Bereich von Nahem
//
// Umbuchungen und Ausgleiche eines Monats: Geld, das sich bewegt hat, ohne etwas zu
// kosten oder zu bringen. Bewusst ohne Farbe, ohne Balken — eine ruhige Liste.

import SwiftUI

struct NeutralSheet: View {
    let store: AppStore
    let month: YearMonth

    @Environment(\.dismiss) private var dismiss

    private var transfers: [Entry] {
        store.data.entries
            .filter { $0.month == month && $0.kind == .transfer }
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }
    private var refunds: [Entry] {
        store.data.entries
            .filter { $0.month == month && $0.kind == .refund && $0.status != .proposed }
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Palette.faint)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Palette.raised))
                        Text(MoneyFormat.amount(transfers.reduce(0) { $0 + $1.amount } + refunds.reduce(0) { $0 + $1.amount }))
                            .font(.system(size: 30, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.muted)
                        Text("bewegt, ohne zu zählen · \(MoneyFormat.month(month))")
                            .font(.caption)
                            .foregroundStyle(Palette.faint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                if !refunds.isEmpty {
                    Section("Ausgleiche") {
                        ForEach(refunds) { entry in row(entry) }
                    }
                }
                if !transfers.isEmpty {
                    Section("Umbuchungen") {
                        ForEach(transfers) { entry in row(entry) }
                    }
                }
                if refunds.isEmpty && transfers.isEmpty {
                    Text("Nichts Neutrales in diesem Monat.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .listRowBackground(Palette.card)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .navigationTitle("Neutral")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }.fontWeight(.semibold).foregroundStyle(Palette.ink)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .tint(Palette.accent)
        .presentationDetents([.medium, .large])
    }

    private func row(_ entry: Entry) -> some View {
        let original = entry.refundOf.flatMap { store.entry($0) }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? (entry.kind == .transfer ? "Umbuchung" : "Ausgleich") : entry.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(MoneyFormat.day(entry.date))
                    if let original {
                        Text("· gleicht aus: \(original.title.isEmpty ? (store.data.category(original.categoryID)?.name ?? "") : original.title)")
                            .lineLimit(1)
                    } else if entry.kind == .refund, let category = store.data.category(entry.categoryID) {
                        Text("· senkt \(category.name)")
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.faint)
            }
            Spacer()
            Text(MoneyFormat.signed(entry.signedAmount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.muted)
            Menu {
                if entry.kind == .refund {
                    Button { store.unlinkRefund(entry.id) } label: {
                        Label("Ausgleich lösen", systemImage: "arrow.uturn.forward")
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
        .listRowBackground(Palette.card)
    }
}
