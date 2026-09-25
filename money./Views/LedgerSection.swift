// LedgerSection.swift
// budget. — die Liste unter der Grafik
//
// Dieselbe Reihenfolge wie im Ring, dieselben Farben. Eine Zeile aufklappen zeigt
// die einzelnen Buchungen dieser Kategorie in diesem Monat. Darunter, wenn es sie
// gibt, die Umbuchungen — als eigene kleine Zeile, weil sie nirgends mitzählen.

import SwiftUI

struct LedgerSection: View {
    let store: AppStore
    let ring: RingSummary
    let month: YearMonth
    var transferTotal: Decimal = 0
    var transferCount: Int = 0
    @Binding var selection: RingSelection?
    @Binding var expanded: UUID?
    let onEdit: (Entry) -> Void
    var onRecategorize: (Entry) -> Void = { _ in }
    var onLink: (Entry) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsTransfers = false

    var body: some View {
        VStack(spacing: 12) {
            CardStack {
                if ring.slices.isEmpty {
                    emptyRow
                } else {
                    ForEach(Array(ring.slices.enumerated()), id: \.element.id) { index, slice in
                        if index > 0 { RowDivider(inset: Metrics.cardPadding + 50) }
                        row(slice)
                        if expanded == slice.id {
                            entryList(for: slice)
                        }
                    }
                }
            }
            if transferCount > 0 { transfersRow }
        }
        .animation(motion, value: expanded)
        .animation(motion, value: ring)
        .animation(motion, value: showsTransfers)
    }

    private var emptyRow: some View {
        VStack(spacing: 4) {
            Text("Keine \(ring.direction.plural) in diesem Monat")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Kategoriezeile

    private func row(_ slice: Slice) -> some View {
        let isSelected = selection?.categoryID == slice.category.id
        return Button {
            toggle(slice)
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    CategoryBadge(category: slice.category, side: 38)

                    HStack(spacing: 6) {
                        Text(slice.category.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        CountChip(count: slice.count)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 6)

                    Text(MoneyFormat.hero(slice.total))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)

                    Text(MoneyFormat.share(slice.share))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Palette.faint)
                        .frame(width: 42, alignment: .trailing)
                }

                shareBar(slice)
                    .padding(.leading, 50)
            }
            .padding(.horizontal, Metrics.cardPadding)
            .padding(.vertical, 12)
            .background(
                Palette.tint(slice.category.tint).opacity(isSelected ? 0.09 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRowStyle())
        .accessibilityLabel(
            "\(slice.category.name), \(MoneyFormat.amount(slice.total)), "
                + "\(MoneyFormat.share(slice.share)) der \(ring.direction.plural)")
        .accessibilityHint(expanded == slice.id ? "Buchungen ausblenden" : "Buchungen anzeigen")
    }

    private func shareBar(_ slice: Slice) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.track)
                Capsule()
                    .fill(Palette.tint(slice.category.tint))
                    .frame(width: max(4, proxy.size.width * slice.share))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    // MARK: - Buchungen einer Kategorie

    private func entryList(for slice: Slice) -> some View {
        VStack(spacing: 0) {
            ForEach(store.entries(of: slice.category.id, in: month)) { entry in
                entryRow(entry, tint: Palette.tint(slice.category.tint))
            }
        }
        .padding(.bottom, 6)
        .background(Palette.raised.opacity(0.5))
        .background(Palette.tint(slice.category.tint).opacity(0.05))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func entryRow(_ entry: Entry, tint: Color) -> some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(tint)
                .frame(width: 3, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(MoneyFormat.day(entry.date))
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                    EntryMarks(entry: entry)
                }
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text((entry.kind == .refund ? "+" : "") + MoneyFormat.amount(entry.amount))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(entry.kind == .refund ? Palette.positive : Palette.muted)

            Menu {
                if entry.source == .manual {
                    Button { onEdit(entry) } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                }
                Button { onRecategorize(entry) } label: {
                    Label("Kategorie ändern", systemImage: "tag")
                }
                if entry.kind == .refund, entry.refundOf != nil {
                    Button { store.unlinkRefund(entry.id) } label: {
                        Label("Ausgleich lösen", systemImage: "arrow.uturn.forward")
                    }
                } else if entry.kind == .flow {
                    Button { onLink(entry) } label: {
                        Label(entry.direction == .income ? "Als Ausgleich zuordnen …" : "Ausgleich zuordnen …",
                              systemImage: "arrow.uturn.backward")
                    }
                }
                if entry.source == .tradeRepublic {
                    Button { store.reject(entry.id, as: .transfer) } label: {
                        Label("Als Umbuchung", systemImage: "arrow.left.arrow.right")
                    }
                }
                Button(role: .destructive) {
                    withAnimation(motion) { store.deleteEntry(entry.id) }
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.faint)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Buchung bearbeiten oder löschen")
        }
        .padding(.leading, Metrics.cardPadding + 6)
        .padding(.trailing, Metrics.cardPadding - 6)
        .padding(.vertical, 7)
    }

    // MARK: - Umbuchungen

    private var transfers: [Entry] {
        store.data.entries
            .filter { $0.kind == .transfer && $0.month == month }
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }

    private var transfersRow: some View {
        CardStack {
            Button {
                showsTransfers.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.faint)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Palette.raised))
                    Text("\(transferCount) Umbuchungen")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Text(MoneyFormat.hero(transferTotal))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.faint)
                        .rotationEffect(.degrees(showsTransfers ? 180 : 0))
                }
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableRowStyle())
            .accessibilityHint("Zählen nirgends mit")

            if showsTransfers {
                VStack(spacing: 0) {
                    ForEach(transfers) { entry in
                        HStack(spacing: 10) {
                            Text(MoneyFormat.day(entry.date))
                                .font(.subheadline)
                                .foregroundStyle(Palette.ink)
                            Text(entry.title)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(MoneyFormat.signed(entry.signedAmount))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(Palette.muted)
                            Menu {
                                Button { onRecategorize(entry) } label: {
                                    Label("Doch zählen — Kategorie wählen", systemImage: "tag")
                                }
                                Button(role: .destructive) { store.deleteEntry(entry.id) } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.faint)
                                    .frame(width: 30, height: 30)
                                    .contentShape(Rectangle())
                            }
                        }
                        .padding(.leading, Metrics.cardPadding + 6)
                        .padding(.trailing, Metrics.cardPadding - 6)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.bottom, 6)
                .background(Palette.raised.opacity(0.5))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Ablauf

    private func toggle(_ slice: Slice) {
        withAnimation(motion) {
            if expanded == slice.id {
                expanded = nil
                selection = nil
            } else {
                expanded = slice.id
                selection = RingSelection(
                    direction: ring.direction, categoryID: slice.category.id)
            }
        }
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1)
    }
}

/// Wie viele Buchungen hinter einer Zeile stecken.
struct CountChip: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Palette.faint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Palette.raised))
            .fixedSize()
            .accessibilityHidden(true)
    }
}
