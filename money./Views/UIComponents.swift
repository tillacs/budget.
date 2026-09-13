import SwiftUI

/// Feedback on press, not on release.
struct PressableRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Palette.ink.opacity(0.05) : .clear)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.spring(duration: 0.3, bounce: 0), value: configuration.isPressed)
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(Palette.muted)
            if let detail {
                Spacer(minLength: 8)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 6)
    }
}

/// Elevation is a hairline plus one soft shadow — enough to lift the card off the canvas,
/// not enough to announce itself.
struct CardStack<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .shadow(
                color: Palette.cardShadow.opacity(Palette.cardShadowOpacity(colorScheme)),
                radius: 7, x: 0, y: 4)
    }
}

struct BudgetBar: View {
    let fraction: Double
    let isOverspent: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule()
                    .fill(isOverspent ? Palette.warn : Palette.accent)
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(height: 4)
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0), value: fraction)
        .accessibilityHidden(true)
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.leading, Metrics.cardPadding)
    }
}
