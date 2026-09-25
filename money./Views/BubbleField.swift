// BubbleField.swift
// budget. — die Vogelperspektive
//
// Ein Monat ist eine Fläche mit Blasen: eine je Kategorie, Fläche nach Summe,
// bewusst ohne Zahl. Drei Schwerkraftzentren — Ausgaben, Einnahmen, Investiert —
// statt Überschriften. Die Blasen finden ihren Platz in einer kleinen
// Kräftesimulation und behalten ihn, wenn der Monat wechselt: Dieselbe Kategorie
// bleibt an ihrem Ort, so wird der Vergleich zweier Monate zur Bewegung.
//
// Drücken und halten zeigt die Zahlen kurz auf allen Blasen. Wer es genau wissen
// will, bekommt es — ohne dass es dauerhaft dasteht.

import SwiftUI

struct Bubble: Identifiable, Hashable {
    let id: String
    let category: BudgetCategory
    let direction: Direction
    let total: Decimal
    let count: Int
    let isPending: Bool

    static func from(_ summary: MonthSummary) -> [Bubble] {
        var result: [Bubble] = []
        for direction in Direction.allCases {
            for slice in summary.ring(direction).slices {
                result.append(Bubble(
                    id: slice.category.id.uuidString, category: slice.category, direction: direction,
                    total: slice.total, count: slice.count, isPending: false))
            }
            for slice in summary.pending[direction] ?? [] {
                result.append(Bubble(
                    id: "p-" + slice.category.id.uuidString, category: slice.category, direction: direction,
                    total: slice.total, count: slice.count, isPending: true))
            }
        }
        return result
    }
}

/// Die Kräftesimulation: Anziehung zum Zentrum der Richtung, Abstoßung zwischen
/// Blasen, Rand. Läuft synchron bis zur Ruhe — bei zwei Dutzend Blasen sind das
/// ein paar Millisekunden.
nonisolated enum BubbleLayout {
    struct Placement: Hashable {
        var center: CGPoint
        var radius: CGFloat
    }

    static func center(for direction: Direction, in size: CGSize) -> CGPoint {
        switch direction {
        case .expense: return CGPoint(x: size.width * 0.36, y: size.height * 0.56)
        case .income: return CGPoint(x: size.width * 0.76, y: size.height * 0.26)
        case .invest: return CGPoint(x: size.width * 0.78, y: size.height * 0.76)
        }
    }

    static func solve(
        _ bubbles: [Bubble], in size: CGSize, previous: [String: Placement]
    ) -> [String: Placement] {
        guard !bubbles.isEmpty, size.width > 0, size.height > 0 else { return [:] }

        // Fläche proportional zur Summe; zusammen füllen die Blasen etwa die Hälfte.
        let values = bubbles.map { max(0.0, $0.total.doubleValue) }
        let sum = values.reduce(0, +)
        let usable = Double(size.width * size.height) * 0.52
        let k = sum > 0 ? sqrt(usable / (.pi * sum)) : 1
        let maxRadius = Double(min(size.width, size.height)) * 0.34
        let minRadius = 16.0

        var radii: [Double] = values.map { min(maxRadius, max(minRadius, k * sqrt($0))) }
        // Falls die Deckelung Platz freigibt oder das Minimum ihn frisst: nachziehen,
        // damit die Fläche wieder zu etwa der Hälfte gefüllt ist.
        let area = radii.reduce(0) { $0 + .pi * $1 * $1 }
        if area > 0 {
            let adjust = min(1.6, max(0.6, sqrt(usable / area)))
            radii = radii.map { min(maxRadius, max(minRadius, $0 * adjust)) }
        }

        var points: [CGPoint] = bubbles.enumerated().map { index, bubble in
            if let old = previous[bubble.id] { return old.center }
            // Neue Blasen starten nahe ihrem Zentrum, leicht versetzt — deterministisch,
            // damit dieselben Daten immer dasselbe Bild ergeben.
            let home = center(for: bubble.direction, in: size)
            let angle = Double(index) * 2.399 // goldener Winkel
            return CGPoint(x: home.x + CGFloat(cos(angle)) * 18, y: home.y + CGFloat(sin(angle)) * 18)
        }

        let gap: CGFloat = 5
        for step in 0..<220 {
            let pull: CGFloat = step < 60 ? 0.045 : 0.03
            for i in bubbles.indices {
                let home = center(for: bubbles[i].direction, in: size)
                points[i].x += (home.x - points[i].x) * pull
                points[i].y += (home.y - points[i].y) * pull
            }
            for i in bubbles.indices {
                for j in (i + 1)..<bubbles.count {
                    let dx = points[j].x - points[i].x
                    let dy = points[j].y - points[i].y
                    var distance = sqrt(dx * dx + dy * dy)
                    let wanted = CGFloat(radii[i] + radii[j]) + gap
                    if distance < 0.01 { distance = 0.01 }
                    guard distance < wanted else { continue }
                    let push = (wanted - distance) / 2
                    let ux = dx / distance, uy = dy / distance
                    points[i].x -= ux * push; points[i].y -= uy * push
                    points[j].x += ux * push; points[j].y += uy * push
                }
            }
            for i in bubbles.indices {
                let r = CGFloat(radii[i])
                points[i].x = min(size.width - r, max(r, points[i].x))
                points[i].y = min(size.height - r, max(r, points[i].y))
            }
        }

        var result: [String: Placement] = [:]
        for (i, bubble) in bubbles.enumerated() {
            result[bubble.id] = Placement(center: points[i], radius: CGFloat(radii[i]))
        }
        return result
    }
}

struct BubbleField: View {
    let summary: MonthSummary
    let onTap: (Bubble) -> Void
    let onPendingTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var placements: [String: BubbleLayout.Placement] = [:]
    @State private var size: CGSize = .zero
    @GestureState private var holding = false
    @State private var appeared = false

    private var bubbles: [Bubble] { Bubble.from(summary) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(bubbles) { bubble in
                    if let placement = placements[bubble.id] {
                        BubbleView(bubble: bubble, radius: placement.radius, showsAmount: holding)
                            .position(placement.center)
                            .onTapGesture { bubble.isPending ? onPendingTap() : onTap(bubble) }
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onAppear { relayout(proxy.size) }
            .onChange(of: proxy.size) { _, new in relayout(new) }
            .onChange(of: summary) { relayout(proxy.size) }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.28)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .updating($holding) { value, state, _ in
                    if case .second = value { state = true }
                })
        .sensoryFeedback(.impact(flexibility: .soft), trigger: holding) { _, new in new }
        .animation(motion, value: placements)
        .animation(.easeOut(duration: 0.18), value: holding)
        .accessibilityElement(children: .contain)
    }

    private func relayout(_ newSize: CGSize) {
        size = newSize
        let previous = placements
        let solved = BubbleLayout.solve(bubbles, in: newSize, previous: previous)
        if placements.isEmpty && !solved.isEmpty && !appeared {
            // Erstes Erscheinen: aus der Mitte heraus wachsen.
            appeared = true
            var seed = solved
            for (id, placement) in solved {
                seed[id] = BubbleLayout.Placement(center: placement.center, radius: placement.radius * 0.2)
            }
            placements = seed
            DispatchQueue.main.async { placements = solved }
        } else {
            placements = solved
        }
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.22)
    }
}

private struct BubbleView: View {
    let bubble: Bubble
    let radius: CGFloat
    let showsAmount: Bool

    private var tint: Color { Palette.tint(bubble.category.tint) }

    var body: some View {
        ZStack {
            if bubble.isPending {
                Circle()
                    .fill(tint.opacity(0.10))
                Circle()
                    .strokeBorder(tint.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            } else {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.7)],
                            center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: radius * 1.3))
                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
            }

            VStack(spacing: 1) {
                Text(bubble.category.symbol)
                    .font(.system(size: max(12, min(34, radius * 0.72))))
                if showsAmount || radius > 44 {
                    Text(showsAmount ? MoneyFormat.hero(bubble.total) : bubble.category.name)
                        .font(.system(size: max(9, min(13, radius * 0.24)), weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(bubble.isPending ? tint : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                }
            }
            .frame(width: radius * 1.9)
        }
        .frame(width: radius * 2, height: radius * 2)
        .shadow(color: bubble.isPending ? .clear : tint.opacity(0.28), radius: radius * 0.25, y: radius * 0.12)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bubble.category.name), \(MoneyFormat.amount(bubble.total))\(bubble.isPending ? ", vorgeschlagen" : "")")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("Blasen") {
    BubbleField(summary: AppStore.preview.summary(for: .current()), onTap: { _ in }, onPendingTap: {})
        .frame(height: 380)
        .background(Palette.canvas)
}
