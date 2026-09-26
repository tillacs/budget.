// UIComponents.swift
// budget. — die kleinen Teile, die auf der einen Seite mehrfach vorkommen

import SwiftUI

/// Die Wortmarke als ruhiges Element im Kopf der Seite — dieselben Proportionen wie
/// in der Startanimation und im App-Icon, damit der Punkt überall gleich sitzt.
struct WordmarkLabel: View {
    var size: CGFloat = 19

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * Wordmark.gapRatio) {
            Text("budget")
                .font(Wordmark.font(size: size))
                .foregroundStyle(Palette.ink)
            Circle()
                .fill(Palette.ink)
                .frame(width: size * Wordmark.dotRatio, height: size * Wordmark.dotRatio)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
        }
        .accessibilityElement()
        .accessibilityLabel("budget.")
    }
}

/// Rückmeldung beim Drücken, nicht beim Loslassen.
struct PressableRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.spring(duration: 0.28, bounce: 0), value: configuration.isPressed)
    }
}

/// Das Zeichen einer Kategorie: Emoji in einem Quadrat, das die Kategorienfarbe
/// trägt. Aus dieser Kachel und der Ringfarbe wird dieselbe Farbe — das ist die
/// ganze Verbindung zwischen Grafik und Liste.
struct CategoryBadge: View {
    let category: BudgetCategory
    var side: CGFloat = 40

    var body: some View {
        let tint = Palette.tint(category.tint)
        RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
            .fill(tint.opacity(0.14))
            .overlay {
                RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                    .strokeBorder(tint, lineWidth: 1.5)
            }
            .overlay {
                Text(category.symbol)
                    .font(.system(size: side * 0.45))
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// Runder Knopf im Kopf der Seite.
struct CircleIconButton: View {
    let systemImage: String
    var diameter: CGFloat = 38
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.4, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Palette.raised))
        }
        .buttonStyle(PressableRowStyle())
    }
}

struct RowDivider: View {
    var inset: CGFloat = Metrics.cardPadding

    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// Fläche mit Haarlinie und einem weichen Schatten — genug, um sie von der
/// Grundfläche abzuheben, nicht genug, um sich anzukündigen.
struct CardStack<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.card))
            // Zeilenhintergründe und Aufgeklapptes bleiben innerhalb der Rundung.
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(
                color: Palette.cardShadow.opacity(Palette.cardShadowOpacity(colorScheme)),
                radius: 8, x: 0, y: 4)
    }
}
