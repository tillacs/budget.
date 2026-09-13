import SwiftUI

/// Creates or edits one category. Templates are a shortcut, never a constraint — a template
/// only prefills the name, the rules and a starting amount, all of which stay editable.
struct CategoryEditorSheet: View {
    let store: AppStore
    /// `nil` creates a new one.
    let category: BudgetCategory?
    var defaultKind: CategoryKind = .spending

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: CategoryKind = .spending
    @State private var amount = ""
    @State private var pickedTemplate: CategoryTemplate?
    @State private var showsDeleteConfirmation = false
    @State private var loaded = false
    @State private var saved = false

    private var isNew: Bool { category == nil }

    private var parsedAmount: Decimal? {
        let normalized = amount
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return nil }
        return TransactionCSVParser.decimal(from: normalized)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                    if isNew { templateSection }
                    detailsSection
                    if !isNew { deleteSection }
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Palette.canvas)
            .navigationTitle(isNew ? "Neu" : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sichern") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .sensoryFeedback(.success, trigger: saved)
        }
        .tint(Palette.accent)
        .onAppear(perform: load)
    }

    // MARK: Sections

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Vorlage", detail: "optional")
            CardStack {
                let templates = CategoryTemplates.templates(for: kind)
                ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                    if index > 0 { RowDivider() }
                    Button { apply(template) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Palette.ink)
                                Text(describe(template))
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if pickedTemplate == template {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                        .padding(Metrics.cardPadding)
                    }
                    .buttonStyle(PressableRowStyle())
                }
            }
        }
    }

    private func describe(_ template: CategoryTemplate) -> String {
        var parts: [String] = []
        if !template.mccCodes.isEmpty {
            parts.append(template.mccCodes.count == 1
                         ? "1 MCC-Regel"
                         : "\(template.mccCodes.count) MCC-Regeln")
        }
        if !template.patterns.isEmpty {
            parts.append(template.patterns.prefix(3).joined(separator: ", "))
        }
        if parts.isEmpty { parts.append("keine Regeln") }
        return parts.joined(separator: " · ")
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Details")
            CardStack {
                HStack {
                    Text("Name").font(.subheadline).foregroundStyle(Palette.muted)
                    Spacer(minLength: 12)
                    TextField("z. B. Lebensmittel", text: $name)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline.weight(.medium))
                }
                .padding(Metrics.cardPadding)

                RowDivider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Art").font(.subheadline).foregroundStyle(Palette.muted)
                    Picker("Art", selection: $kind) {
                        Text("Ausgabe").tag(CategoryKind.spending)
                        Text("Laufend").tag(CategoryKind.fixed)
                        Text("Einnahme").tag(CategoryKind.income)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(Metrics.cardPadding)

                if kind != .income {
                    RowDivider()
                    HStack {
                        Text(kind == .fixed ? "Erwartet" : "Budget")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                        Spacer(minLength: 12)
                        TextField("0", text: $amount)
                            .multilineTextAlignment(.trailing)
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .keyboardType(.decimalPad)
                        Text("€").font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    .padding(Metrics.cardPadding)
                }
            }

            if kind == .income {
                Text("Einnahmen haben kein Budget — hier zählt nur, was tatsächlich reinkam.")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardStack {
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    HStack {
                        Text("Kategorie löschen")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.warn)
                        Spacer()
                    }
                    .padding(Metrics.cardPadding)
                }
                .buttonStyle(PressableRowStyle())
            }
            Text("Regeln und Zuordnungen dieser Kategorie werden entfernt. Die Buchungen selbst bleiben und landen wieder im Inbox.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 6)
        }
        .alert("Kategorie löschen?", isPresented: $showsDeleteConfirmation) {
            Button("Löschen", role: .destructive) {
                if let category { store.deleteCategory(category.id) }
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let category {
            name = category.name
            kind = category.kind
            if let budget = store.data.budgets[category.id] {
                amount = MoneyFormat.plain(budget)
            }
        } else {
            kind = defaultKind
        }
    }

    private func apply(_ template: CategoryTemplate) {
        pickedTemplate = template
        name = template.name
        kind = template.kind
        amount = template.suggestedBudget.map(MoneyFormat.plain) ?? ""
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let id: BudgetCategory.ID
        if let category {
            store.renameCategory(category.id, to: trimmed)
            store.setKind(kind, for: category.id)
            id = category.id
        } else if let template = pickedTemplate, template.name == trimmed, template.kind == kind {
            // Picked a template and left it alone — bring its rules along.
            id = store.addCategory(from: template).id
        } else {
            id = store.addCategory(name: trimmed, kind: kind).id
        }

        store.setBudget(kind == .income ? 0 : (parsedAmount ?? 0), for: id)
        saved.toggle()
        dismiss()
    }
}
