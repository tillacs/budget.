// SettingsSheet.swift
// budget. — Kategorien und die Einrichtung des Doppeltipps
//
// Das einzige, was hinter der einen Seite liegt. Es ist nichts, was man im Alltag
// braucht: die Kategorien gehören hierher, weil man sie einmal anlegt, und die
// Anleitung, weil man den Doppeltipp genau einmal einrichtet.

import SwiftUI
import UIKit

struct SettingsSheet: View {
    let store: AppStore

    @Environment(\.dismiss) private var dismiss

    @State private var editingCategory: BudgetCategory?
    @State private var newCategoryDirection: Direction?
    @State private var showsResetConfirmation = false
    /// Eigener Schalter statt `EditButton`: Der heißt in einer App ohne deutsche
    /// Lokalisierung „Edit", und das ist das einzige englische Wort weit und breit.
    @State private var isSorting = false

    var body: some View {
        NavigationStack {
            List {
                backTapSection
                actionsSection
                categorySection(.expense)
                categorySection(.income)
                dataSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .environment(\.editMode, .constant(isSorting ? .active : .inactive))
            .navigationTitle("Einrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSorting ? "Fertig" : "Sortieren") {
                        withAnimation { isSorting.toggle() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schließen") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .tint(Palette.accent)
        .sheet(item: $editingCategory) { category in
            CategoryEditorSheet(store: store, editing: category)
        }
        .sheet(item: $newCategoryDirection) { direction in
            CategoryEditorSheet(store: store, editing: nil, direction: direction)
        }
        .confirmationDialog(
            "Wirklich alles löschen?", isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Alles löschen", role: .destructive) { store.resetAllData() }
        } message: {
            Text("Alle Buchungen und Kategorien werden entfernt. Das lässt sich nicht rückgängig machen.")
        }
    }

    // MARK: - Doppeltipp

    private var backTapSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                step(1, "In der Kurzbefehle-App einen neuen Kurzbefehl anlegen und eine "
                    + "der Aktionen von budget. hinzufügen — welche, steht unten.")
                step(2, "In den Einstellungen: Bedienungshilfen → Tippen → "
                    + "Auf Rückseite tippen → Doppeltippen.")
                step(3, "Ganz unten unter \u{201E}Kurzbefehle\u{201C} den neuen Kurzbefehl auswählen.")

                Button {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                } label: {
                    Text("Kurzbefehle öffnen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.canvas)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(Palette.ink))
                }
                .buttonStyle(PressableRowStyle())
                .padding(.top, 2)
            }
            .padding(.vertical, 6)
            .listRowBackground(Palette.card)
        } header: {
            Text("Doppeltipp auf die Rückseite")
        } footer: {
            Text("Danach genügt zweimal Tippen auf die Rückseite des iPhones.")
        }
    }

    /// Drei Aktionen, und sie unterscheiden sich in genau einer Frage: Will man den
    /// Ziffernblock der App — oder will man bleiben, wo man gerade ist?
    private var actionsSection: some View {
        Section {
            actionRow(
                "Buchung erfassen",
                "Fragt in zwei Einblendungen nach Kategorie und Betrag und bucht, ohne "
                    + "budget. zu öffnen. Man bleibt in der App, in der man gerade war.")
            actionRow(
                "Ausgabe erfassen",
                "Öffnet budget. im Ziffernblock, mit vorausgewählter Kategorie. Der "
                    + "schnellere Weg, wenn man ohnehin auf die Ringe schauen will.")
            actionRow(
                "Einnahme erfassen",
                "Dasselbe für Einnahmen — passt gut auf den Dreifachtipp.")
        } header: {
            Text("Die drei Aktionen")
        }
    }

    private func actionRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .listRowBackground(Palette.card)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.canvas)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.ink))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Kategorien

    private func categorySection(_ direction: Direction) -> some View {
        Section {
            ForEach(store.data.categories(for: direction)) { category in
                Button { editingCategory = category } label: {
                    HStack(spacing: 12) {
                        CategoryBadge(category: category, side: 34)
                        Text(category.name)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.faint)
                    }
                }
                .listRowBackground(Palette.card)
            }
            .onMove { source, destination in
                store.moveCategories(for: direction, from: source, to: destination)
            }

            Button { newCategoryDirection = direction } label: {
                Label("Neue Kategorie", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.accent)
            }
            .listRowBackground(Palette.card)
        } header: {
            Text(direction.plural)
        }
    }

    // MARK: - Daten

    private var dataSection: some View {
        Section {
            Button(role: .destructive) { showsResetConfirmation = true } label: {
                Text("Alles löschen")
            }
            .listRowBackground(Palette.card)
        } footer: {
            Text("budget. speichert ausschließlich auf diesem Gerät — keine Konten, kein Import, "
                + "keine Übertragung.")
        }
    }
}

#Preview("Einrichten") {
    SettingsSheet(store: .preview)
}
