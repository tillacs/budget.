// CategoriesPage.swift
// budget. — die zweite Seite, einen Wisch nach links
//
// Oben die Kategorien, weil man die gelegentlich anfasst. Unten die Einrichtung des
// Doppeltipps, weil man die genau einmal braucht und danach nie wieder.

import SwiftUI
import UIKit

struct CategoriesPage: View {
    let store: AppStore

    @State private var editingCategory: BudgetCategory?
    @State private var newCategoryDirection: Direction?
    @State private var showsResetConfirmation = false
    /// Eigener Schalter statt `EditButton`: Der heißt in einer App ohne deutsche
    /// Lokalisierung „Edit", und das ist das einzige englische Wort weit und breit.
    @State private var isSorting = false

    var body: some View {
        NavigationStack {
            List {
                categorySection(.expense)
                categorySection(.income)
                actionsSection
                backTapSection
                walletSection
                dataSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .environment(\.editMode, .constant(isSorting ? .active : .inactive))
            .navigationTitle("Kategorien")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSorting ? "Fertig" : "Sortieren") {
                        withAnimation { isSorting.toggle() }
                    }
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
            actionRow(
                "Buchung vorschlagen",
                "Bekommt einen Text, liest Betrag und Händler heraus und fragt nach, "
                    + "bevor sie bucht. Für Automationen gedacht — siehe unten.")
        } header: {
            Text("Die vier Aktionen")
        } footer: {
            Text("Beim Erfassen darf hinter dem Betrag eine Notiz stehen: "
                + "\u{201E}12,50 Bäcker\u{201C} bucht 12,50 € mit der Notiz Bäcker. "
                + "budget. merkt sich, welche Kategorie zu \u{201E}Bäcker\u{201C} gehört.")
        }
    }

    /// Der einzige Auslöser, den iOS für Zahlungen hergibt.
    ///
    /// Mitteilungen anderer Apps kann keine App lesen — es gibt dafür weder eine
    /// Schnittstelle noch einen Automations-Auslöser. Was von Trade Republic oder
    /// PayPal als Push kommt, bleibt deshalb außen vor. Läuft die Zahlung dagegen über
    /// Apple Pay, greift der Wallet-Auslöser.
    private var walletSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                step(1, "Kurzbefehle → Automation → Neue Automation → Wallet, "
                    + "dann die Karte auswählen.")
                step(2, "\u{201E}Nach Bestätigung ausführen\u{201C} wählen — so kommt ein "
                    + "Vorschlag statt einer stillen Buchung.")
                step(3, "Als Aktion \u{201E}Buchung vorschlagen\u{201C} aus budget. wählen.")
            }
            .padding(.vertical, 6)
            .listRowBackground(Palette.card)
        } header: {
            Text("Automatisch bei Apple Pay")
        } footer: {
            Text("Nach jeder Zahlung mit dieser Karte fragt das iPhone, ob budget. sie "
                + "buchen soll. Push-Mitteilungen von Banking-Apps kann unter iOS keine "
                + "App lesen — nur Zahlungen über Apple Pay lösen etwas aus.")
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

#Preview("Kategorien") {
    CategoriesPage(store: .preview)
}
