// LedgerSection.swift
// budget. — die Liste unter den Ringen
//
// Dieselbe Reihenfolge wie im Ring, dieselben Farben. Eine Zeile aufklappen zeigt
// die einzelnen Buchungen dieser Kategorie in diesem Monat — das ist die tiefste
// Ebene der App, und sie liegt auf derselben Seite.

import SwiftUI

struct LedgerSection: View {
    let store: AppStore
    let ring: RingSummary
    let month: YearMonth
    @Binding var selection: RingSelection?
    @Binding var expanded: UUID?
    let onEdit: (Entry) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CardStack {
            if ring.slices.isEmpty {
                emptyRow
            } else {
                ForEach(Array(ring.slices.enumerated()), id: \.element.id) { index, slice in
                    if index > 0 { RowDivider(inset: Metrics.cardPadding + 52) }
                    row(slice)
                    if expanded == slice.id {
                        entryList(for: slice)
                    }
                }
            }
        }
        .animation(motion, value: expanded)
        .animation(motion, value: ring)
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
        Button {
            toggle(slice)
        } label: {
            HStack(spacing: 10) {
                CategoryBadge(category: slice.category)

                HStack(spacing: 6) {
                    Text(slice.category.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    CountChip(count: slice.count)
                }
                // Der Name gibt als Letztes nach: Zahlen kann man kürzen, einen
                // abgeschnittenen Kategorienamen kann man nicht lesen.
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
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(Palette.raised))
                    .frame(width: 50, alignment: .trailing)
            }
            .padding(.horizontal, Metrics.cardPadding)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRowStyle())
        .accessibilityLabel(
            "\(slice.category.name), \(MoneyFormat.amount(slice.total)), "
                + "\(MoneyFormat.share(slice.share)) der \(ring.direction.plural)")
        .accessibilityHint(expanded == slice.id ? "Buchungen ausblenden" : "Buchungen anzeigen")
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
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func entryRow(_ entry: Entry, tint: Color) -> some View {
        HStack(spacing: 12) {
            // Ein kurzer Strich in der Kategorienfarbe statt einer zweiten Kachel —
            // die Zugehörigkeit ist schon klar, sie braucht nur eine Spur.
            Capsule()
                .fill(tint)
                .frame(width: 3, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(MoneyFormat.day(entry.date))
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(MoneyFormat.amount(entry.amount))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.muted)

            Menu {
                Button { onEdit(entry) } label: {
                    Label("Bearbeiten", systemImage: "pencil")
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
            .accessibilityHidden(true)
    }
}
