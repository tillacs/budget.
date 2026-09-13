import SwiftUI

/// One tap on a category commits. The rule that tap will write is shown above the list and
/// can be swapped first — the user should never be surprised by what got learned.
struct CategorizeSheet: View {
    let group: InboxGroup
    let store: AppStore

    @Environment(\.dismiss) private var dismiss
    @State private var choice: RuleChoice = .automatic
    @State private var showsNewCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryKind: CategoryKind = .spending
    @State private var committed = false

    private var proposals: [Rule] {
        // categoryID is a placeholder here; the real one is filled in on commit.
        RuleProposal.proposals(for: group.representative, categoryID: UUID())
    }

    private var choices: [RuleChoice] {
        proposals.indices.map { RuleChoice.proposal($0) } + [.onlyThese]
    }

    private var activeChoice: RuleChoice {
        if case .automatic = choice { return choices.first ?? .onlyThese }
        return choice
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                    header
                    ruleSection
                    categorySection
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Palette.canvas)
            .navigationTitle("Zuordnen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: committed)
        }
        .tint(Palette.accent)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 6)
    }

    private var subtitle: String {
        var parts: [String] = [
            group.count == 1 ? "1 Buchung" : "\(group.count) Buchungen",
            MoneyFormat.amount(group.total),
        ]
        if let mcc = group.mcc { parts.append("MCC \(mcc)") }
        return parts.joined(separator: " · ")
    }

    // MARK: Rule choice

    private var ruleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Regel")
            CardStack {
                ForEach(Array(choices.enumerated()), id: \.element) { index, option in
                    if index > 0 { RowDivider() }
                    Button {
                        choice = option
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label(for: option))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Palette.ink)
                                Text(detail(for: option))
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                            }
                            Spacer(minLength: 8)
                            if option == activeChoice {
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

    private func label(for option: RuleChoice) -> String {
        switch option {
        case .automatic:
            return label(for: activeChoice)
        case .onlyThese:
            return group.count == 1 ? "Nur diese Buchung" : "Nur diese \(group.count) Buchungen"
        case .proposal(let index):
            guard index < proposals.count else { return "—" }
            switch proposals[index].matcher {
            case .mcc(let code): return "MCC \(code)"
            case .pattern(let pattern): return "Text „\(pattern.text)“"
            }
        }
    }

    private func detail(for option: RuleChoice) -> String {
        switch option {
        case .automatic:
            return detail(for: activeChoice)
        case .onlyThese:
            return "Schreibt keine Regel — der Händler fragt beim nächsten Mal wieder."
        case .proposal(let index):
            guard index < proposals.count else { return "" }
            switch proposals[index].matcher {
            case .mcc:
                return "Gilt für alle Karten­zahlungen mit diesem Code."
            case .pattern(let pattern):
                return "Gilt für alles, worin „\(pattern.text)“ vorkommt."
            }
        }
    }

    // MARK: Categories

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Kategorie")
            CardStack {
                ForEach(Array(sortedCategories.enumerated()), id: \.element.id) { index, category in
                    if index > 0 { RowDivider() }
                    Button {
                        commit(to: category.id)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Palette.ink)
                                Text(kindLabel(category.kind))
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                            }
                            Spacer(minLength: 8)
                            if group.suggestion?.categoryID == category.id {
                                Text(confidenceLabel)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                        .padding(Metrics.cardPadding)
                    }
                    .buttonStyle(PressableRowStyle())
                }

                RowDivider()
                Button {
                    showsNewCategory = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.semibold))
                        Text("Neue Kategorie")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .foregroundStyle(Palette.accent)
                    .padding(Metrics.cardPadding)
                }
                .buttonStyle(PressableRowStyle())
            }

            if let evidence = group.suggestion?.evidence, !evidence.isEmpty {
                Text("Vorschlag wegen \(evidence.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 6)
            }
        }
        .alert("Neue Kategorie", isPresented: $showsNewCategory) {
            TextField("Name", text: $newCategoryName)
            Button("Anlegen") { createCategory() }
            Button("Abbrechen", role: .cancel) { newCategoryName = "" }
        } message: {
            Text("Die Kategorie wird als Ausgabe angelegt. Art und Budget lassen sich in den Einstellungen ändern.")
        }
    }

    /// Suggested category first, then the user's own order.
    private var sortedCategories: [BudgetCategory] {
        store.data.categories.sorted { left, right in
            let leftSuggested = left.id == group.suggestion?.categoryID
            let rightSuggested = right.id == group.suggestion?.categoryID
            if leftSuggested != rightSuggested { return leftSuggested }
            return left.sortIndex < right.sortIndex
        }
    }

    private var confidenceLabel: String {
        guard let confidence = group.suggestion?.confidence else { return "Vorschlag" }
        return "Vorschlag · \(Int((confidence * 100).rounded())) %"
    }

    private func kindLabel(_ kind: CategoryKind) -> String {
        switch kind {
        case .spending: return "Ausgabe"
        case .income: return "Einnahme"
        case .fixed: return "Laufende Kosten"
        }
    }

    // MARK: Commit

    private func createCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        newCategoryName = ""
        guard !name.isEmpty else { return }
        let category = store.addCategory(name: name, kind: newCategoryKind)
        commit(to: category.id)
    }

    private func commit(to categoryID: BudgetCategory.ID) {
        var rule: Rule?
        if case .proposal(let index) = activeChoice, index < proposals.count {
            rule = Rule(categoryID: categoryID, matcher: proposals[index].matcher)
        }
        store.categorize(group, as: categoryID, writing: rule)
        committed.toggle()
        dismiss()
    }
}

enum RuleChoice: Hashable {
    /// Whatever the first proposal is — MCC when the booking has one, otherwise the name.
    case automatic
    case proposal(Int)
    case onlyThese
}
