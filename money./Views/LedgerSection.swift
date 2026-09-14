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
                    if index > 0 { RowDivider(inset: Metrics.cardPadding + 50) }
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
                        .frame(width: 42, alignment: .trailing)
                }

                // Der Balken bekommt eine eigene Ebene, statt in der Zeile um Platz
                // zu konkurrieren — sonst drängt er die Beträge aus dem Bild.
                shareBar(slice)
                    .padding(.leading, 50)
            }
            .padding(.horizontal, Metrics.cardPadding)
            .padding(.vertical, 12)
            // Die ausgewählte Zeile trägt einen Hauch ihrer eigenen Farbe. Damit
            // schließt sich der Kreis zum Ring: dort leuchtet dasselbe Segment.
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

    /// Der Anteil als Strich in der Kategorienfarbe.
    ///
    /// Die Prozentzahl daneben sagt dasselbe, aber man muss sie lesen. Der Strich
    /// macht aus der Liste ein Bild: Man sieht die Rangfolge, ohne eine einzige Zahl
    /// anzusehen — und es ist dieselbe Farbe wie im Ring darüber.
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
        // Derselbe Farbhauch wie in der Zeile darüber: Aufgeklapptes gehört sichtbar
        // zu der Kategorie, aus der es kommt.
        .background(Palette.raised.opacity(0.5))
        .background(Palette.tint(slice.category.tint).opacity(0.05))
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
