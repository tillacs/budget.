// Glass.swift
// budget. — die kleinen Bausteine aus Liquid Glass
//
// Glas nur für das, was über der Fläche liegt: Chips, Pillen, Blätter. Die Fläche
// selbst bleibt matt — Glas auf Glas verschwindet im Rauschen.

import SwiftUI

extension View {
    /// Eine Kapsel aus Glas. `interactive` lässt sie beim Drücken nachgeben.
    func glassCapsule(interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(GlassCapsule(interactive: interactive, tint: tint))
    }
}

private struct GlassCapsule: ViewModifier {
    let interactive: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return content.glassEffect(glass, in: .capsule)
    }
}

/// Wie sicher die Maschine war: satt, halb, hohl. Keine Prozentzahl.
struct ConfidenceDot: View {
    let band: ConfidenceBand
    var tint: Color = Palette.ink

    var body: some View {
        ZStack {
            Circle().strokeBorder(tint, lineWidth: 1.5)
            switch band {
            case .sure:
                Circle().fill(tint).padding(1.5)
            case .likely:
                Circle()
                    .trim(from: 0, to: 0.5)
                    .fill(tint)
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
            case .unsure:
                EmptyView()
            }
        }
        .frame(width: 10, height: 10)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch band {
        case .sure: return "sicher"
        case .likely: return "wahrscheinlich"
        case .unsure: return "unsicher"
        }
    }
}

/// Ein Kategorie-Chip aus Glas: Zeichen, Name, in der Farbe der Kategorie.
struct CategoryChip: View {
    let category: BudgetCategory
    var isOn = false
    var compact = false

    var body: some View {
        let tint = Palette.tint(category.tint)
        HStack(spacing: 6) {
            Text(category.symbol).font(.system(size: compact ? 13 : 15))
            Text(category.name)
                .font(compact ? .caption.weight(.medium) : .subheadline.weight(isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? Palette.ink : Palette.muted)
                .lineLimit(1)
        }
        .padding(.vertical, compact ? 6 : 9)
        .padding(.horizontal, compact ? 10 : 14)
        .glassCapsule(interactive: true, tint: isOn ? tint.opacity(0.35) : nil)
        .overlay(Capsule().strokeBorder(isOn ? tint : .clear, lineWidth: 1.5))
    }
}

/// Zeigt, woher eine Buchung kommt und ob die Maschine sie gebucht hat.
struct EntryMarks: View {
    let entry: Entry

    var body: some View {
        HStack(spacing: 4) {
            if entry.kind == .refund {
                Text("Erstattung").font(.caption2.weight(.medium)).foregroundStyle(Palette.positive)
            }
            if entry.status == .autoBooked {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.faint)
                    .accessibilityLabel("automatisch gebucht")
            }
            if entry.source == .tradeRepublic {
                Image(systemName: "creditcard")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.faint)
                    .accessibilityLabel("aus Trade Republic")
            }
        }
    }
}
