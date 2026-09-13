import SwiftUI

/// Packs circles into centred rows. A grid would waste the space around round shapes and
/// make the size differences harder to read.
struct BubbleLayout: Layout {
    var spacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 360
        let rows = rows(of: subviews, within: width)
        let height = rows.reduce(CGFloat.zero) { total, row in
            total + row.height + (total > 0 ? spacing : 0)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        var y = bounds.minY
        for row in rows(of: subviews, within: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    // Sit the circles on a shared baseline so a row reads as one shelf.
                    at: CGPoint(x: x, y: y + row.height - size.height),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(of subviews: Subviews, within width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, projected > width {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// A budget as a circle: area proportional to the amount, filling up from the bottom as the
/// month is spent. Size answers "how big is this budget", fill answers "how far along am I".
struct BudgetBubble: View {
    let progress: SpendingProgress
    let diameter: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { progress.isOverspent ? Palette.warn : Palette.accent }
    private var fillOpacity: Double { colorScheme == .dark ? 0.34 : 0.20 }

    var body: some View {
        ZStack {
            Circle().fill(Palette.card)

            // The waterline: a rectangle clipped to the circle, so the level reads at a
            // glance without any numbers.
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack(alignment: .top) {
                        Rectangle().fill(tint.opacity(fillOpacity))
                        Rectangle().fill(tint).frame(height: 1.5)
                    }
                    .frame(height: proxy.size.height * progress.fraction)
                }
            }
            .clipShape(Circle())
            .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0), value: progress.fraction)

            // A dashed edge says "no limit set" without needing a word for it.
            if progress.hasBudget {
                Circle().strokeBorder(Palette.hairline, lineWidth: 1)
            } else {
                Circle().strokeBorder(
                    Palette.faint, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            VStack(spacing: 2) {
                Text(progress.category.name)
                    .font(.system(size: max(11, diameter * 0.105), weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text(MoneyFormat.rounded(progress.hasBudget ? progress.remaining : progress.spent))
                    .font(.system(size: max(13, diameter * 0.145), weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.4)
                    .foregroundStyle(
                        progress.isOverspent
                            ? Palette.warn
                            : (progress.hasBudget ? Palette.ink : Palette.muted))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, diameter * 0.14)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        progress.hasBudget
            ? "\(progress.category.name), \(MoneyFormat.amount(progress.remaining)) übrig von \(MoneyFormat.amount(progress.budget))"
            : "\(progress.category.name), \(MoneyFormat.amount(progress.spent)) ausgegeben, kein Budget"
    }
}

/// Area grows with the amount, so a 400 € budget looks twice the 100 € one rather than four
/// times — that is how circles read.
enum BubbleSize {
    static let minimum: CGFloat = 78
    static let maximum: CGFloat = 168

    static func diameter(for amount: Decimal, largest: Decimal, scale: CGFloat = 1) -> CGFloat {
        guard largest > 0, amount > 0 else { return minimum * scale }
        let ratio = min(1, max(0, (amount / largest).doubleValue))
        let size = minimum + (maximum - minimum) * CGFloat(ratio.squareRoot())
        return size * scale
    }
}
