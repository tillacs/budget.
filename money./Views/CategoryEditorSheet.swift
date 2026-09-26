// CategoryEditorSheet.swift
// budget. — eine Kategorie anlegen oder ändern
//
// Name, Zeichen, Farbe, Seite. Mehr kann eine Kategorie in dieser App nicht sein,
// und das ist Absicht: Jede weitere Einstellung wäre eine Entscheidung, die man
// beim Erfassen wieder nachschlagen müsste.

import SwiftUI

struct CategoryEditorSheet: View {
    let store: AppStore
    let editing: BudgetCategory?
    var direction: Direction = .expense
    var onSave: ((BudgetCategory) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var symbol = "💫"
    @State private var tint: CategoryTint = .azure
    @State private var currentDirection: Direction = .expense
    @State private var showsDeleteConfirmation = false
    @State private var showsMovePicker = false
    @State private var prepared = false
    @FocusState private var nameFocused: Bool

    private var entryCount: Int {
        editing.map { store.entryCount(in: $0.id) } ?? 0
    }

    /// Mit Buchungen darf eine Kategorie die Geldrichtung nicht mehr wechseln — eine
    /// Ausgabe wird nicht zur Einnahme, nur weil ihre Kategorie umzieht. Zwischen
    /// Ausgaben und Investiert geht es weiter.
    private func isSideAllowed(_ candidate: Direction) -> Bool {
        guard let editing, entryCount > 0 else { return true }
        return Direction.compatible(with: editing.direction).contains(candidate)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Ein Vorrat gängiger Zeichen. Wer ein anderes will, tippt es in das Feld neben
    /// dem Namen — die Emoji-Tastatur ist der einzige Symbolwähler, den jeder kennt.
    private let suggestions = [
        "🍽️", "🛒", "🏠", "🚆", "⛽️", "🎧", "🎉", "🧾", "💊", "👕",
        "✈️", "📱", "🔁", "🐾", "🎁", "📚", "🏋️", "☕️", "🍺", "🚕",
        "💼", "💰", "📈", "🎓", "🧰", "✨", "💫", "🧩",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    preview
                    nameField
                    symbolGrid
                    tintRow
                    directionRow
                    if editing != nil { deleteButton }
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.vertical, 18)
            }
            .background(Palette.canvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editing == nil ? "Neue Kategorie" : "Kategorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save).disabled(!canSave).fontWeight(.semibold)
                }
            }
        }
        .tint(Palette.accent)
        .presentationDetents([.large])
        .task { prepare() }
        .confirmationDialog(
            "\u{201E}\(name)\u{201C} löschen?",
            isPresented: $showsDeleteConfirmation, titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let editing { store.deleteCategory(editing.id) }
                dismiss()
            }
        } message: {
            Text("Die Kategorie ist leer. Das lässt sich nicht rückgängig machen.")
        }
        // Mit Buchungen: auflösen — einzeln umordnen oder alle auf einmal.
        .sheet(isPresented: $showsMovePicker) {
            if let editing {
                DissolveCategorySheet(store: store, category: editing) { dismiss() }
            }
        }
    }

    // MARK: - Teile

    private var preview: some View {
        VStack(spacing: 10) {
            CategoryBadge(
                category: BudgetCategory(name: name, symbol: symbol, tint: tint, direction: currentDirection),
                side: 76)
            Text(name.isEmpty ? "Ohne Namen" : name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(name.isEmpty ? Palette.faint : Palette.ink)
        }
        .padding(.top, 6)
    }

    private var nameField: some View {
        HStack(spacing: 10) {
            TextField("Zeichen", text: $symbol)
                .font(.system(size: 22))
                .multilineTextAlignment(.center)
                .frame(width: 52, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.raised))
                .onChange(of: symbol) { _, new in
                    // Ein Zeichen genügt — und es muss nicht zwingend ein Emoji sein.
                    if let first = new.first { symbol = String(first) }
                }

            TextField("Name", text: $name)
                .font(.body)
                .focused($nameFocused)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.raised))
        }
    }

    private var symbolGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Zeichen")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8
            ) {
                ForEach(suggestions, id: \.self) { candidate in
                    Button { symbol = candidate } label: {
                        Text(candidate)
                            .font(.system(size: 20))
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(symbol == candidate ? Palette.card : Palette.raised))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        symbol == candidate ? Palette.ink : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(PressableRowStyle())
                }
            }
        }
    }

    private var tintRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Farbe")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10
            ) {
                ForEach(CategoryTint.all, id: \.rawValue) { candidate in
                    Button { tint = candidate } label: {
                        Circle()
                            .fill(Palette.tint(candidate))
                            .frame(height: 38)
                            .overlay {
                                if tint == candidate {
                                    Circle()
                                        .strokeBorder(Palette.canvas, lineWidth: 3)
                                        .padding(2)
                                }
                            }
                            .overlay {
                                if tint == candidate {
                                    Circle().strokeBorder(Palette.ink, lineWidth: 1.5)
                                }
                            }
                    }
                    .buttonStyle(PressableRowStyle())
                    .accessibilityLabel(candidate.rawValue)
                    .accessibilityAddTraits(tint == candidate ? [.isSelected] : [])
                }
            }
        }
    }

    private var directionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Seite")
            HStack(spacing: 4) {
                ForEach(Direction.allCases, id: \.self) { candidate in
                    let isOn = currentDirection == candidate
                    let allowed = isSideAllowed(candidate)
                    Button { if allowed { currentDirection = candidate } } label: {
                        Text(candidate.plural)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isOn ? Palette.canvas : (allowed ? Palette.muted : Palette.faint.opacity(0.5)))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background { if isOn { Capsule().fill(Palette.ink) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
            }
            .padding(4)
            .background(Capsule().fill(Palette.raised))

            if editing != nil {
                Text(entryCount > 0
                     ? "Die Buchungen ziehen mit um. Zwischen rein und raus kann eine Kategorie mit Buchungen nicht wechseln."
                     : "Wechselt die Seite, ziehen die bisherigen Buchungen dieser Kategorie mit um.")
                    .font(.caption)
                    .foregroundStyle(Palette.faint)
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            if entryCount > 0 { showsMovePicker = true } else { showsDeleteConfirmation = true }
        } label: {
            Text(entryCount > 0 ? "Auflösen — \(entryCount) Buchungen umordnen …" : "Kategorie löschen")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.negative)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.negative.opacity(0.10)))
        }
        .buttonStyle(PressableRowStyle())
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(Palette.muted)
    }

    // MARK: - Ablauf

    private func prepare() {
        guard !prepared else { return }
        prepared = true

        if let editing {
            name = editing.name
            symbol = editing.symbol
            tint = editing.tint
            currentDirection = editing.direction
        } else {
            currentDirection = direction
            // Ein Ton, der noch nicht vergeben ist — zwei gleichfarbige Segmente wären
            // im Ring nicht auseinanderzuhalten.
            let used = Set(store.data.categories.map(\.tint.rawValue))
            tint = CategoryTint.all.first { !used.contains($0.rawValue) } ?? .azure
            nameFocused = true
        }
    }

    private func save() {
        let saved: BudgetCategory
        if var editing {
            editing.name = name
            editing.symbol = symbol
            editing.tint = tint
            editing.direction = currentDirection
            store.updateCategory(editing)
            saved = editing
        } else {
            saved = store.addCategory(
                name: name, symbol: symbol, tint: tint, direction: currentDirection)
        }
        onSave?(saved)
        dismiss()
    }
}

#Preview("Kategorie") {
    CategoryEditorSheet(store: .preview, editing: nil)
}
