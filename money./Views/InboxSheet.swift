// InboxSheet.swift
// budget. — der Posteingang
//
// Was die Maschine nicht sicher wusste, wartet hier: je Zeile Betrag, Händler,
// Tag, die vorgeschlagene Kategorie als Chip und die Begründung in einem Satz.
// Wischen nach rechts nimmt an — der Chip rastet bei 40 % spürbar ein, davor
// federt er zurück. Wischen nach links lehnt ab. Tipp auf den Chip zeigt die
// drei besten Kategorien; antippen bestätigt sofort.

import SwiftUI

/// Vorschläge desselben Händlers in derselben Richtung stehen zusammen: Eine
/// Entscheidung für „EDEKA, 19 Buchungen" ist eine Entscheidung — und die Maschine
/// lernt sie neunzehnfach.
struct InboxGroup: Identifiable, Hashable {
    let id: String
    let entries: [Entry]

    var lead: Entry { entries[0] }
    var count: Int { entries.count }
    var total: Decimal { entries.reduce(0) { $0 + $1.signedAmount } }
    var ids: [UUID] { entries.map(\.id) }

    static func make(_ proposals: [Entry]) -> [InboxGroup] {
        var order: [String] = []
        var buckets: [String: [Entry]] = [:]
        for entry in proposals {
            let key = (entry.signals.merchantKey ?? entry.externalID ?? entry.id.uuidString)
                + "|" + entry.direction.rawValue + "|" + entry.kind.rawValue
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }
        return order.map { InboxGroup(id: $0, entries: buckets[$0] ?? []) }
            .sorted { a, b in
                a.count == b.count ? a.lead.date > b.lead.date : a.count > b.count
            }
    }
}

struct InboxSheet: View {
    let store: AppStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var acceptedAll = 0
    @State private var pickerFor: InboxGroup?

    private var proposals: [Entry] { store.proposals }
    private var groups: [InboxGroup] { InboxGroup.make(proposals) }
    private var confidentCount: Int {
        proposals.filter { ($0.suggestion?.band ?? .unsure) != .unsure }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if confidentCount > 0 { acceptAllButton }
                    if proposals.isEmpty {
                        emptyState
                    }
                    ForEach(groups) { group in
                        InboxRow(store: store, group: group) { pickerFor = group }
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.vertical, 12)
                .animation(motion, value: groups.map(\.id))
            }
            .background(Palette.canvas)
            .navigationTitle(proposals.isEmpty ? "Posteingang"
                             : "\(proposals.count) Vorschläge · \(groups.count) Händler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .tint(Palette.accent)
        .sheet(item: $pickerFor) { group in
            CategoryPickerSheet(store: store, direction: group.lead.direction, current: group.lead.categoryID) {
                store.correct(group.ids, to: $0)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: acceptedAll)
    }

    private var acceptAllButton: some View {
        Button {
            acceptedAll += store.acceptAllConfident()
        } label: {
            Label("\(confidentCount) sichere annehmen", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.canvas)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(Palette.ink)
        .padding(.bottom, 6)
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

/// Eine Zeile im Posteingang, mit der Wischgeste.
private struct InboxRow: View {
    let store: AppStore
    let group: InboxGroup
    let onMore: () -> Void

    private var entry: Entry { group.lead }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var crossed = false
    @State private var expanded = false
    @State private var showsReject = false
    @State private var leaving = false
    @State private var accepted = 0

    private var category: BudgetCategory? { store.data.category(entry.categoryID) }
    private var tint: Color { category.map { Palette.tint($0.tint) } ?? Palette.faint }

    var body: some View {
        GeometryReader { proxy in
            let threshold = proxy.size.width * 0.4
            ZStack {
                backdrop
                card
                    .offset(x: offset)
                    .gesture(drag(threshold: threshold, width: proxy.size.width))
            }
            .onChange(of: offset) { _, new in
                let now = abs(new) >= threshold
                if now != crossed { crossed = now }
            }
        }
        .frame(height: expanded ? 158 : 104)
        .animation(motion, value: expanded)
        .sensoryFeedback(.selection, trigger: crossed) { _, new in new }
        .sensoryFeedback(.success, trigger: accepted)
        .confirmationDialog("Gehört nicht hierher?", isPresented: $showsReject, titleVisibility: .visible) {
            Button("Als Umbuchung behalten") { store.reject(group.ids, as: .transfer) }
            Button("Verwerfen", role: .destructive) { store.reject(group.ids, as: .delete) }
            Button("Abbrechen", role: .cancel) { withAnimation(motion) { offset = 0 } }
        } message: {
            Text("Eine Umbuchung zählt nirgends mit. Verworfen kommt die Zeile beim nächsten Import nicht wieder.")
        }
    }

    private var backdrop: some View {
        HStack {
            Image(systemName: "checkmark")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .opacity(offset > 12 ? 1 : 0)
                .scaleEffect(crossed && offset > 0 ? 1.15 : 1)
                .padding(.leading, 24)
            Spacer()
            Image(systemName: "xmark")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .opacity(offset < -12 ? 1 : 0)
                .scaleEffect(crossed && offset < 0 ? 1.15 : 1)
                .padding(.trailing, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(offset > 0 ? Palette.positive : (offset < 0 ? Palette.negative : Palette.raised))
                .opacity(min(1, abs(offset) / 60)))
        .animation(.spring(duration: 0.25, bounce: 0), value: crossed)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Erste Zeile: wer und wie viel. Der Name gibt zuletzt nach.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.title.isEmpty ? "Ohne Namen" : entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if group.count > 1 { CountChip(count: group.count) }
                Spacer(minLength: 8)
                // Der Betrag gibt nie nach — ein abgeschnittener Betrag ist keiner.
                Text(MoneyFormat.signed(group.total))
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(group.total > 0 ? Palette.positive : Palette.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(2)
            }
            // Zweite Zeile: die Kategorie zum Antippen, rechts der Tag.
            HStack(spacing: 8) {
                chipButton
                Spacer(minLength: 4)
                Text(group.count > 1 ? "zuletzt \(MoneyFormat.day(entry.date))" : MoneyFormat.day(entry.date))
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
            }
            if expanded { alternatives }
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var chipButton: some View {
        Button {
            withAnimation(motion) { expanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                if let category { CategoryChip(category: category, isOn: true, compact: true) }
                ConfidenceDot(band: entry.suggestion?.band ?? .unsure, tint: tint)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kategorie: \(category?.name ?? "keine"), andere wählen")
    }

    private var alternatives: some View {
        let ids = [entry.categoryID] + (entry.suggestion?.alternatives ?? [])
        let options = ids.compactMap { store.data.category($0) }
        return GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    Button {
                        accepted += 1
                        store.correct(group.ids, to: option.id)
                    } label: {
                        CategoryChip(category: option, isOn: option.id == entry.categoryID, compact: true)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onMore) {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 34, height: 30)
                        .glassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Alle Kategorien")
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func drag(threshold: CGFloat, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) || offset != 0 else { return }
                let raw = value.translation.width
                // Rubber-Banding hinter der Schwelle: es geht weiter, aber zäher.
                let limit = threshold * 1.15
                offset = abs(raw) <= limit ? raw : (raw < 0 ? -1 : 1) * (limit + (abs(raw) - limit) * 0.25)
            }
            .onEnded { value in
                if offset >= threshold {
                    accepted += 1
                    withAnimation(.spring(duration: 0.3, bounce: 0)) { offset = width }
                    Task {
                        try? await Task.sleep(for: .seconds(0.12))
                        store.accept(group.ids)
                    }
                } else if offset <= -threshold {
                    showsReject = true
                } else {
                    withAnimation(motion) { offset = 0 }
                }
            }
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2)
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
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
        .tint(Palette.accent)
        .presentationDetents([.medium, .large])
    }
}
