// DissolveCategorySheet.swift
// budget. — eine Kategorie auflösen, Buchung für Buchung
//
// Löschen nimmt nie Buchungen mit. Hier stehen alle, die an der Kategorie hängen:
// Jede lässt sich einzeln in eine andere Kategorie schieben, oder oben alle
// verbleibenden auf einmal. Erst wenn nichts mehr dranhängt, geht die Kategorie.

import SwiftUI

struct DissolveCategorySheet: View {
    let store: AppStore
    let category: BudgetCategory
    /// Wird gerufen, wenn die Kategorie weg ist — der Editor darunter schließt dann mit.
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickerFor: Entry?
    @State private var showsMoveAll = false
    @State private var moved = 0

    private var entries: [Entry] {
        store.data.entries
            .filter { $0.categoryID == category.id }
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }
    private var allowed: [Direction] { Direction.compatible(with: category.direction) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if entries.isEmpty {
                        Button {
                            store.deleteCategory(category.id)
                            dismiss()
                            onDeleted()
                        } label: {
                            Label("Kategorie jetzt löschen", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.negative)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glass)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        Button { showsMoveAll = true } label: {
                            Label("Alle \(entries.count) nach … umbuchen", systemImage: "arrow.right.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.canvas)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Palette.ink)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } footer: {
                    Text(entries.isEmpty
                         ? "Nichts hängt mehr an \u{201E}\(category.name)\u{201C}."
                         : "Oder unten jede Buchung einzeln: Tipp auf den Chip, Ziel wählen.")
                }
                if !entries.isEmpty {
                    Section("Einzeln umordnen") {
                        ForEach(entries) { entry in
                            row(entry)
                                .listRowBackground(Palette.card)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .animation(motion, value: entries.map(\.id))
            .navigationTitle("\u{201E}\(category.name)\u{201C} auflösen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }.foregroundStyle(Palette.ink).fontWeight(.semibold)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .tint(Palette.accent)
        .presentationDetents([.large])
        .sheet(item: $pickerFor) { entry in
            CategoryPickerSheet(
                store: store, direction: entry.direction, current: nil, exclude: category.id,
                allowed: entry.compatibleDirections, title: "Wohin mit \(MoneyFormat.amount(entry.amount))?"
            ) { target in
                moved += 1
                store.correct([entry.id], to: target, announce: false)
            }
        }
        .sheet(isPresented: $showsMoveAll) {
            CategoryPickerSheet(
                store: store, direction: category.direction, current: nil, exclude: category.id,
                allowed: allowed, title: "Alle \(entries.count) umbuchen nach …"
            ) { target in
                store.deleteCategory(category.id, movingEntriesTo: target)
                dismiss()
                onDeleted()
            }
        }
        .sensoryFeedback(.selection, trigger: moved)
    }

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? category.name : entry.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(MoneyFormat.dayLong(entry.date))
                    EntryMarks(entry: entry)
                    if entry.status == .proposed {
                        Text("Vorschlag").foregroundStyle(Palette.faint)
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.faint)
            }
            Spacer(minLength: 6)
            Text(MoneyFormat.signed(entry.signedAmount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(entry.signedAmount > 0 ? Palette.positive : Palette.ink)
                .fixedSize()
            Button { pickerFor = entry } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                    Text("Wohin?")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(Palette.ink)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .glassCapsule(interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Buchung umordnen")
        }
        .padding(.vertical, 2)
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.1)
    }
}
