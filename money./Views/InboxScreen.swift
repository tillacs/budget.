import SwiftUI

/// The Inbox has no payload of its own, so it needs a distinct route value.
enum InboxRoute: Hashable {
    case inbox
}

struct InboxScreen: View {
    let store: AppStore

    @State private var selected: InboxGroup?

    private var groups: [InboxGroup] { store.inboxGroups }

    var body: some View {
        Group {
            if groups.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Palette.canvas)
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { group in
            CategorizeSheet(group: group, store: store)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.muted)
            Text("Alles zugeordnet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text("Neue Buchungen tauchen hier auf, wenn keine Regel greift.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Metrics.screenInset)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Offen", detail: summary)
                CardStack {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { RowDivider() }
                        Button {
                            selected = group
                        } label: {
                            InboxRow(group: group, store: store)
                        }
                        .buttonStyle(PressableRowStyle())
                    }
                }
            }
            .padding(.horizontal, Metrics.screenInset)
            .padding(.top, 4)
            .padding(.bottom, 48)
        }
    }

    private var summary: String {
        let bookings = groups.reduce(0) { $0 + $1.count }
        let shops = groups.count == 1 ? "1 Händler" : "\(groups.count) Händler"
        let count = bookings == 1 ? "1 Buchung" : "\(bookings) Buchungen"
        return "\(count) · \(shops)"
    }
}

struct InboxRow: View {
    let group: InboxGroup
    let store: AppStore

    private var suggestedName: String? {
        guard let suggestion = group.suggestion else { return nil }
        return store.data.categories.first { $0.id == suggestion.categoryID }?.name
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)

                if let suggestedName {
                    Text("Vorschlag: \(suggestedName)")
                        .font(.caption)
                        .foregroundStyle(Palette.accent)
                }
            }
            Spacer(minLength: 8)
            Text(MoneyFormat.amount(group.total))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .padding(Metrics.cardPadding)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(group.count == 1 ? "1 Buchung" : "\(group.count) Buchungen")
        parts.append(group.count == 1 || group.earliest == group.latest
                     ? MoneyFormat.day(group.latest)
                     : "\(MoneyFormat.day(group.earliest)) – \(MoneyFormat.day(group.latest))")
        if let mcc = group.mcc { parts.append("MCC \(mcc)") }
        return parts.joined(separator: " · ")
    }
}
