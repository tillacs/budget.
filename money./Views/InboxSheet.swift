// InboxSheet.swift
// budget. — der Posteingang
//
// Was die Maschine nicht sicher wusste, wartet hier: je Zeile Betrag, Händler,
// Tag, die vorgeschlagene Kategorie als Chip und die Begründung in einem Satz.
// Wischen nach rechts nimmt an, Wischen nach links lehnt ab. Tipp auf den Chip
// zeigt die drei besten Kategorien; antippen bestätigt sofort.
//
// Kartenzahlungen desselben Händlers stehen als Gruppe — eine Entscheidung für
// „EDEKA, 19 Buchungen" ist eine Entscheidung. Überweisungen und Geld an Personen
// stehen immer einzeln: Wer sich dreimal Geld schickt, meint dreimal etwas anderes.
// Jede Gruppe lässt sich mit einem Tipp auf die Zahl in Einzelne auflösen.

import SwiftUI

struct InboxGroup: Identifiable, Hashable {
    let id: String
    let entries: [Entry]

    var lead: Entry { entries[0] }
    var count: Int { entries.count }
    var total: Decimal { entries.reduce(0) { $0 + $1.signedAmount } }
    var ids: [UUID] { entries.map(\.id) }

    /// Nur Kartenzahlungen bei Händlern und Depot-Buchungen werden gebündelt.
    static func isGroupable(_ entry: Entry) -> Bool {
        guard let type = entry.importType else { return false }
        if type.hasPrefix("TRANSFER") { return false }
        if entry.mcc == "4829" || entry.mcc == "6012" { return false }   // Geld an Personen
        if entry.kind == .refund { return false }
        return entry.signals.merchantKey != nil
    }

    static func make(_ proposals: [Entry], split: Set<String>) -> [InboxGroup] {
        var order: [String] = []
        var buckets: [String: [Entry]] = [:]
        for entry in proposals {
            let key: String
            if isGroupable(entry), let merchant = entry.signals.merchantKey {
                key = merchant + "|" + entry.direction.rawValue + "|" + entry.kind.rawValue
            } else {
                key = entry.id.uuidString
            }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }
        var groups: [InboxGroup] = order.map { key in
            InboxGroup(id: key, entries: buckets[key] ?? [])
        }
        groups.sort { (a: InboxGroup, b: InboxGroup) -> Bool in
            if a.count != b.count { return a.count > b.count }
            return a.lead.date > b.lead.date
        }
        // Aufgelöste Gruppen stehen als Einzelne an derselben Stelle.
        return groups.flatMap { group -> [InboxGroup] in
            guard group.count > 1, split.contains(group.id) else { return [group] }
            return group.entries.map { InboxGroup(id: $0.id.uuidString, entries: [$0]) }
        }
    }
}

struct InboxSheet: View {
    let store: AppStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var accepted = 0
    @State private var rejected = 0
    @State private var pickerFor: InboxGroup?
    @State private var linkFor: Entry?
    @State private var rejecting: InboxGroup?
    @State private var expanded: Set<String> = []
    @State private var split: Set<String> = []

    private var proposals: [Entry] { store.proposals }
    private var groups: [InboxGroup] { InboxGroup.make(proposals, split: split) }
    private var confidentCount: Int {
        proposals.filter { ($0.suggestion?.band ?? .unsure) != .unsure }.count
    }

    var body: some View {
        NavigationStack {
            list
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Palette.canvas)
                .animation(motion, value: groups.map(\.id))
                .navigationTitle(proposals.isEmpty ? "Posteingang" : "\(proposals.count) offen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }.fontWeight(.semibold).foregroundStyle(Palette.ink)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
        }
        .tint(Palette.accent)
        .sheet(item: $pickerFor) { group in
            CategoryPickerSheet(store: store, direction: group.lead.direction, current: group.lead.categoryID) {
                accepted += 1
                store.correct(group.ids, to: $0)
            }
        }
        .sheet(item: $linkFor) { entry in
            RefundLinkSheet(store: store, entry: entry)
        }
        .sensoryFeedback(.success, trigger: accepted)
        .sensoryFeedback(.warning, trigger: rejected)
    }

    private var list: some View {
        List {
            if confidentCount > 0 {
                acceptAllButton
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: Metrics.screenInset, bottom: 8, trailing: Metrics.screenInset))
            }
            if proposals.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(groups) { group in
                row(group)
            }
        }
    }

    private func row(_ group: InboxGroup) -> some View {
        InboxRow(
            store: store, group: group,
            isExpanded: expanded.contains(group.id),
            onToggle: { withAnimation(motion) { toggle(group.id) } },
            onSplit: { withAnimation(motion) { _ = split.insert(group.id) } },
            onMore: { pickerFor = group },
            onPick: { category in
                accepted += 1
                store.correct(group.ids, to: category)
            },
            onLink: { linkFor = group.lead })
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: Metrics.screenInset, bottom: 5, trailing: Metrics.screenInset))
        .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingActions(group) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingActions(group) }
    }

    @ViewBuilder
    private func leadingActions(_ group: InboxGroup) -> some View {
        if !(group.lead.suggestion?.isGuess ?? true) {
            Button {
                accepted += 1
                store.accept(group.ids)
            } label: {
                Label("Annehmen", systemImage: "checkmark")
            }
            .tint(Palette.positive)
        }
    }

    @ViewBuilder
    private func trailingActions(_ group: InboxGroup) -> some View {
        Button(role: .destructive) {
            rejected += 1
            store.reject(group.ids, as: .delete)
        } label: {
            Label("Verwerfen", systemImage: "trash")
        }
        Button {
            rejected += 1
            store.reject(group.ids, as: .transfer)
        } label: {
            Label("Umbuchung", systemImage: "arrow.left.arrow.right")
        }
        .tint(Palette.muted)
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private var acceptAllButton: some View {
        Button {
            accepted += store.acceptAllConfident()
        } label: {
            Label("\(confidentCount) sichere annehmen", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.canvas)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(Palette.ink)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.faint)
            Text("Nichts offen")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("Alles, was der Export gebracht hat, ist eingeordnet.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.15)
    }
}

/// Eine Zeile im Posteingang.
private struct InboxRow: View {
    let store: AppStore
    let group: InboxGroup
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSplit: () -> Void
    let onMore: () -> Void
    let onPick: (UUID) -> Void
    let onLink: () -> Void

    private var entry: Entry { group.lead }
    private var category: BudgetCategory? { store.data.category(entry.categoryID) }
    private var tint: Color { category.map { Palette.tint($0.tint) } ?? Palette.faint }
    /// Ein Vorschlag ohne Grund ist keiner — dann steht „Wofür?" statt einer Kategorie.
    private var isGuess: Bool { entry.suggestion?.isGuess ?? true }
    /// Ein Ausgleich: Das Geld senkt eine Ausgabe, statt Einnahme zu sein.
    private var linkedOriginal: Entry? {
        guard entry.kind == .refund, let id = entry.refundOf else { return nil }
        return store.entry(id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.title.isEmpty ? "Ohne Namen" : entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if group.count > 1 {
                    Button(action: onSplit) {
                        HStack(spacing: 3) {
                            Text("\(group.count)")
                            Image(systemName: "rectangle.split.3x1")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.raised))
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(group.count) Buchungen, einzeln anzeigen")
                }
                Spacer(minLength: 8)
                Text(MoneyFormat.signed(group.total))
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(group.total > 0 ? Palette.positive : Palette.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(2)
            }
            HStack(spacing: 8) {
                chipButton
                Spacer(minLength: 4)
                Text((group.count > 1 ? "zuletzt " : "") + dateLabel)
                    .font(.caption)
                    .foregroundStyle(Palette.faint)
            }
            if let suggestion = entry.suggestion, !suggestion.reason.isEmpty {
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            } else if entry.kind == .refund {
                Text("Erstattung — wofür war das?")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            } else if isGuess {
                Text("Noch nichts gelernt — bitte einmal zuordnen.")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            if isExpanded { alternatives }
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1))
        .contentShape(Rectangle())
    }

    /// Außerhalb des laufenden Monats steht das Datum mit Jahr — damit klar ist, in
    /// welchem Monat die Buchung nach der Entscheidung zu finden ist.
    private var dateLabel: String {
        entry.date.yearMonth == .current() ? MoneyFormat.day(entry.date) : MoneyFormat.dayLong(entry.date)
    }

    private var chipButton: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                if let original = linkedOriginal {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption.weight(.bold))
                        Text("Ausgleich: \(original.title.isEmpty ? (category?.name ?? "") : original.title)")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .glassCapsule(interactive: true, tint: tint.opacity(0.35))
                    .overlay(Capsule().strokeBorder(tint, lineWidth: 1.5))
                    ConfidenceDot(band: entry.suggestion?.band ?? .unsure, tint: tint)
                } else if isGuess {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark")
                            .font(.caption.weight(.bold))
                        Text("Wofür?")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .glassCapsule(interactive: true)
                } else if let category {
                    CategoryChip(category: category, isOn: true, compact: true)
                    ConfidenceDot(band: entry.suggestion?.band ?? .unsure, tint: tint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isGuess ? "Kategorie wählen" : "Kategorie: \(category?.name ?? "keine"), andere wählen")
    }

    private var alternatives: some View {
        // Bei einem Ausgleich stehen als Alternativen die Einnahme-Kategorien:
        // „nein, das war wirklich Geld für mich".
        let ids = (isGuess || linkedOriginal != nil ? [] : [entry.categoryID]) + (entry.suggestion?.alternatives ?? [])
        let options = ids.compactMap { store.data.category($0) }
        // Scrollbar, damit bei langen Namen nichts über den Rand fällt — und „Andere"
        // steht vorn, damit es immer erreichbar ist.
        return ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: onMore) {
                        HStack(spacing: 5) {
                            Image(systemName: "ellipsis")
                                .font(.caption.weight(.bold))
                            Text("Andere")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .glassCapsule(interactive: true)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Alle Kategorien")
                    if entry.kind == .flow {
                        // „Das ist kein Geld für mich, das gleicht eine Ausgabe aus."
                        Button(action: onLink) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.caption.weight(.bold))
                                Text("Ausgleich")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(Palette.ink)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .glassCapsule(interactive: true)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Als Ausgleich einer Ausgabe zuordnen")
                    }
                    ForEach(options) { option in
                        Button { onPick(option.id) } label: {
                            CategoryChip(category: option, isOn: !isGuess && option.id == entry.categoryID, compact: true)
                                .frame(minHeight: 34)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        // Bis an die Kartenkante scrollen, aber nie darüber hinaus: Der Rand der
        // Karte ist auch der Rand der Reihe.
        .contentMargins(.horizontal, Metrics.cardPadding, for: .scrollContent)
        .padding(.horizontal, -Metrics.cardPadding)
        .clipped()
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Alle Kategorien zur Auswahl — die drei besten standen schon als Chips da.
struct CategoryPickerSheet: View {
    let store: AppStore
    let direction: Direction
    let current: UUID?
    let onPick: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Direction.allCases, id: \.self) { candidate in
                    let categories = store.data.categories(for: candidate)
                    if !categories.isEmpty {
                        Section(candidate.plural) {
                            ForEach(categories) { category in
                                Button {
                                    onPick(category.id)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        CategoryBadge(category: category, side: 32)
                                        Text(category.name).foregroundStyle(Palette.ink)
                                        Spacer()
                                        if category.id == current {
                                            Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                                        }
                                    }
                                }
                                .listRowBackground(Palette.card)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .navigationTitle("Wohin?")
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
}
