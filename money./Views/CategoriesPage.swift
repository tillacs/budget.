// CategoriesPage.swift
// budget. — die zweite Seite, einen Wisch nach links
//
// Oben die Kategorien in drei Bereichen, weil man die gelegentlich anfasst.
// Darunter Konten & Import — der Export von Trade Republic, der Kontoinhaber, die
// Automatik-Schwelle. Ganz unten der Doppeltipp, weil man den genau einmal braucht.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CategoriesPage: View {
    let store: AppStore
    /// Zurück zur Mitte — für das X oben rechts, wenn man nicht wischen will.
    var onClose: () -> Void = {}

    @State private var editingCategory: BudgetCategory?
    @State private var newCategoryDirection: Direction?
    @State private var showsResetConfirmation = false
    @State private var showsImportResetConfirmation = false
    @State private var showsForgetConfirmation = false
    @State private var showsImporter = false
    @State private var importError: String?
    @State private var ownerName = ""
    @State private var isSorting = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(Direction.allCases, id: \.self) { categorySection($0) }
                importSection
                ownerSection
                automationSection
                actionsSection
                backTapSection
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
                    .foregroundStyle(Palette.muted)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 34, height: 34)
                            .glassCapsule(interactive: true)
                    }
                    .buttonStyle(PressableRowStyle())
                    .accessibilityLabel("Zurück zur Übersicht")
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .tint(Palette.accent)
        .task { ownerName = store.data.ownerName ?? "" }
        .sheet(item: $editingCategory) { category in
            CategoryEditorSheet(store: store, editing: category)
        }
        .sheet(item: $newCategoryDirection) { direction in
            CategoryEditorSheet(store: store, editing: nil, direction: direction)
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.commaSeparatedText, .delimitedText, .plainText, .text]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    try store.importTradeRepublic(try ImportFile.read(url))
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Import nicht möglich", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .confirmationDialog(
            "Eingelesene Buchungen entfernen?", isPresented: $showsImportResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Entfernen", role: .destructive) { store.resetImport() }
        } message: {
            Text("Alle Buchungen aus Trade Republic verschwinden, auch die bestätigten. Kategorien und Gelerntes bleiben. Der nächste Export bringt alles wieder.")
        }
        .confirmationDialog(
            "Gelerntes vergessen?", isPresented: $showsForgetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Vergessen", role: .destructive) { store.forgetLearning() }
        } message: {
            Text("budget. weiß danach nichts mehr über Händler und Kategorien. Buchungen bleiben.")
        }
        .confirmationDialog(
            "Wirklich alles löschen?", isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Alles löschen", role: .destructive) { store.resetAllData() }
        } message: {
            Text("Alle Buchungen, Kategorien und alles Gelernte werden entfernt. Das lässt sich nicht rückgängig machen.")
        }
    }

    // MARK: - Import

    private var importSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let stamp = store.data.lastImport {
                    HStack(spacing: 10) {
                        Image(systemName: "creditcard")
                            .foregroundStyle(Palette.muted)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Trade Republic · bis \(MoneyFormat.day(stamp.newestDate))")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.ink)
                            Text("Zuletzt eingelesen \(stamp.date.formatted(.dateTime.day().month().year()))")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                } else {
                    Text("Noch kein Export eingelesen.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }

                Button { showsImporter = true } label: {
                    Label("Export einlesen", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.canvas)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.ink)
            }
            .padding(.vertical, 6)
            .listRowBackground(Palette.card)
        } header: {
            Text("Konten & Import")
        } footer: {
            Text("In der Trade-Republic-App: Kontoauszüge → Transaktionsexport → Teilen → budget. "
                + "Der Export enthält immer alles; was schon da ist, wird übersprungen. "
                + "Erstattungen senken ihre Kategorie, Umbuchungen zählen nicht.")
        }
    }

    private var ownerSection: some View {
        Section {
            TextField("Name wie auf dem Konto", text: $ownerName)
                .textContentType(.name)
                .autocorrectionDisabled()
                .onSubmit { store.setOwnerName(ownerName) }
                .onChange(of: ownerName) { _, new in
                    if new.trimmingCharacters(in: .whitespaces) != (store.data.ownerName ?? "") {
                        store.setOwnerName(new)
                    }
                }
                .listRowBackground(Palette.card)

            let candidates = store.candidateOwnIBANs
            if !candidates.isEmpty {
                ForEach(candidates, id: \.iban) { candidate in
                    Button { store.toggleOwnIBAN(candidate.iban) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.name)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.ink)
                                Text(candidate.iban)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Image(systemName: store.data.ownIBANs.contains(candidate.iban)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(store.data.ownIBANs.contains(candidate.iban)
                                                 ? Palette.accent : Palette.faint)
                        }
                    }
                    .listRowBackground(Palette.card)
                }
            }
        } header: {
            Text("Kontoinhaber")
        } footer: {
            Text("Überweisungen an diesen Namen gelten als Umbuchung auf ein eigenes Konto. "
                + "Darunter die Konten, an die schon Geld ging — abhaken, was deins ist.")
        }
    }

    private var automationSection: some View {
        Section {
            Picker("Automatik", selection: Binding(
                get: { thresholdChoice },
                set: { store.setAutoThreshold($0) })
            ) {
                Text("nie").tag(1.0)
                Text("vorsichtig").tag(0.95)
                Text("mutig").tag(0.9)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Palette.card)
        } header: {
            Text("Selbst buchen")
        } footer: {
            Text("Erst wenn ein Händler zweimal bestätigt wurde, bucht budget. ihn von allein — "
                + "und zeigt es mit ✦. Jede automatische Buchung lässt sich umsortieren.")
        }
    }

    private var thresholdChoice: Double {
        let value = store.data.autoThreshold
        if value >= 1 { return 1.0 }
        return value >= 0.95 ? 0.95 : 0.9
    }

    // MARK: - Doppeltipp

    private var backTapSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                step(1, "In der Kurzbefehle-App einen neuen Kurzbefehl anlegen und eine "
                    + "der Aktionen von budget. hinzufügen — welche, steht oben.")
                step(2, "In den Einstellungen: Bedienungshilfen → Tippen → "
                    + "Auf Rückseite tippen → Doppeltippen.")
                step(3, "Ganz unten unter \u{201E}Kurzbefehle\u{201C} den neuen Kurzbefehl auswählen.")

                Button {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                } label: {
                    Text("Kurzbefehle öffnen")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                .padding(.top, 2)
            }
            .padding(.vertical, 6)
            .listRowBackground(Palette.card)
        } header: {
            Text("Doppeltipp auf die Rückseite")
        } footer: {
            Text("Danach genügt zweimal Tippen auf die Rückseite des iPhones. Was von Hand "
                + "erfasst wird, löst der nächste Export ein — nichts zählt doppelt.")
        }
    }

    private var actionsSection: some View {
        Section {
            actionRow(
                "Buchung erfassen",
                "Fragt in zwei Einblendungen nach Kategorie und Betrag und bucht, ohne "
                    + "budget. zu öffnen. Man bleibt in der App, in der man gerade war.")
            actionRow(
                "Ausgabe erfassen",
                "Öffnet budget. im Ziffernblock, mit vorausgewählter Kategorie.")
            actionRow(
                "Einnahme erfassen",
                "Dasselbe für Einnahmen — passt gut auf den Dreifachtipp.")
        } header: {
            Text("Die drei Aktionen")
        } footer: {
            Text("Beim Erfassen darf hinter dem Betrag eine Notiz stehen: "
                + "\u{201E}12,50 Bäcker\u{201C} bucht 12,50 € mit der Notiz Bäcker. "
                + "budget. merkt sich, welche Kategorie zu \u{201E}Bäcker\u{201C} gehört.")
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
            Button { showsImportResetConfirmation = true } label: {
                Label("Eingelesene Buchungen entfernen", systemImage: "arrow.uturn.backward")
                    .foregroundStyle(Palette.ink)
            }
            .listRowBackground(Palette.card)
            Button { showsForgetConfirmation = true } label: {
                Label("Gelerntes vergessen", systemImage: "brain")
                    .foregroundStyle(Palette.ink)
            }
            .listRowBackground(Palette.card)
            Button(role: .destructive) { showsResetConfirmation = true } label: {
                Text("Alles löschen")
            }
            .listRowBackground(Palette.card)
        } header: {
            Text("Verlauf")
        } footer: {
            Text("budget. speichert ausschließlich auf diesem Gerät — kein Konto, keine Übertragung. "
                + "Der Export wird gelesen und nicht behalten. Eingelesenes lässt sich entfernen "
                + "und mit dem nächsten Export neu aufbauen; Gelerntes bleibt dabei erhalten.")
        }
    }
}

#Preview("Kategorien") {
    CategoriesPage(store: .preview) {}
}
