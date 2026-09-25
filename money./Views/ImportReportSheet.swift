// ImportReportSheet.swift
// budget. — was der Import gebracht hat
//
// Eine Zusammenfassung, keine Tabelle: wie viele Zeilen, wie viele davon schon
// bekannt, was die Maschine selbst gebucht hat und was im Posteingang wartet.
// Und ob die Prüfsumme stimmt — steht sie nicht, steht die Differenz da.

import SwiftUI

struct ImportReportSheet: View {
    let report: ImportReport
    let onOpenInbox: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(Palette.hairline).frame(width: 36, height: 5).padding(.top, 8)

            VStack(spacing: 4) {
                Text(report.imported == 0 ? "Nichts Neues" : "\(report.imported) neue Buchungen")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text("\(report.rows) Zeilen im Export, \(report.alreadyKnown) davon schon bekannt")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }

            VStack(spacing: 0) {
                line("automatisch gebucht", report.autoBooked, "sparkle")
                line("Vorschläge im Posteingang", report.proposed, "tray")
                line("Buchungen von Hand übernommen", report.adopted, "hand.tap")
                line("Erstattungen verknüpft", report.refundsLinked, "arrow.uturn.backward")
                line("Umbuchungen", report.transfers, "arrow.left.arrow.right")
                line("Saveback-Paare", report.savebackPairs, "gift")
                line("Zeilen ohne Betrag", report.withoutAmount, "minus.circle")
            }
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))

            checksum

            Spacer(minLength: 0)

            if report.proposed > 0 {
                Button(action: onOpenInbox) {
                    Text("Posteingang öffnen")
                        .font(.headline)
                        .foregroundStyle(Palette.canvas)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.ink)
            } else {
                Button("Fertig") { dismiss() }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, Metrics.screenInset)
        .padding(.bottom, 16)
        .background(Palette.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func line(_ label: String, _ count: Int, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(count > 0 ? Palette.ink : Palette.faint)
                .frame(width: 22)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(count > 0 ? Palette.ink : Palette.faint)
            Spacer()
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(count > 0 ? Palette.ink : Palette.faint)
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var checksum: some View {
        if report.isBalanced {
            Label("Prüfsumme stimmt mit Trade Republic überein", systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(Palette.positive)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("Prüfsumme weicht ab", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.negative)
                ForEach(report.mismatchedMonths, id: \.self) { month in
                    Text("\(MoneyFormat.month(month)): \(MoneyFormat.signed(report.checksum[month] ?? 0))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
