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
    @State private var showsAdd = false
    @State private var linkFor: Entry?

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
                    Text("Nichts Neutrales in diesem Monat. Über \u{201E}Hinzufügen\u{201C} lässt sich jede Buchung hierher verschieben.")
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
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsAdd = true } label: {
                        Label("Hinzufügen", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.ink)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }.fontWeight(.semibold).foregroundStyle(Palette.ink)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .tint(Palette.accent)
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showsAdd) {
            NeutralAddSheet(store: store, month: month)
        }
        .sheet(item: $linkFor) { entry in
            RefundLinkSheet(store: store, entry: entry)
        }
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
                } else {
                    // Eine Umbuchung, die in Wahrheit eine Ausgabe verringert: direkt der
                    // Buchung zuordnen, nicht einer Kategorie.
                    if entry.isInflow {
                        Button { linkFor = entry } label: {
                            Label("Als Ausgleich einer Ausgabe zuordnen …", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Button { store.restoreFromNeutral(entry.id) } label: {
                        Label("Doch zählen — Kategorie wählen", systemImage: "tag")
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

/// Eine Buchung nach Neutral holen: alle zählenden Buchungen, der gewählte Monat
/// zuerst, mit Suche nach Name, Kategorie oder Betrag.
struct NeutralAddSheet: View {
    let store: AppStore
    let month: YearMonth

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var moved = 0

    private var candidates: [Entry] {
        store.data.entries
            .filter { $0.counts && $0.kind == .flow }
            .sorted { a, b in
                let am = a.month == month, bm = b.month == month
                if am != bm { return am }
                return (a.date, a.createdAt) > (b.date, b.createdAt)
            }
    }

    private var matching: [Entry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return Array(candidates.prefix(200)) }
        return candidates.filter { item in
            let category = store.data.category(item.categoryID)?.name ?? ""
            return [item.title, item.note, item.merchant ?? "", category,
                    MoneyFormat.amount(item.amount), MoneyFormat.plain(item.amount)]
                .joined(separator: " ").lowercased().contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(matching) { entry in
                        Button {
                            moved += 1
                            store.reject(entry.id, as: .transfer)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                if let category = store.data.category(entry.categoryID) {
                                    CategoryBadge(category: category, side: 32)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.title.isEmpty ? (store.data.category(entry.categoryID)?.name ?? "Ohne Namen") : entry.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    Text("\(MoneyFormat.dayLong(entry.date)) · \(store.data.category(entry.categoryID)?.name ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(Palette.faint)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(MoneyFormat.signed(entry.signedAmount))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(entry.signedAmount > 0 ? Palette.positive : Palette.ink)
                            }
                        }
                        .listRowBackground(Palette.card)
                    }
                } header: {
                    Text("Nach Neutral verschieben")
                } footer: {
                    Text("Die Buchung zählt danach nirgends mehr mit und lässt sich unter Neutral wieder einer Kategorie geben.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, Kategorie oder Betrag")
            .navigationTitle("Hinzufügen")
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
        .sensoryFeedback(.success, trigger: moved)
    }
}
