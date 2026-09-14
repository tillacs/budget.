// FlowRings.swift
// budget. — die zwei Ringe
//
// Außen die Ausgaben, innen die Einnahmen. Beide teilen sich einen Maßstab: Der
// größere Betrag füllt seinen Kreis ganz, der kleinere kommt entsprechend kürzer
// herum. Die offene Strecke des kürzeren Rings ist damit exakt der Überschuss —
// die Grafik behauptet nichts, sie misst.
//
// Innerhalb eines Rings ist jedes Segment eine Kategorie, im Uhrzeigersinn ab
// zwölf Uhr, größte zuerst. Ein Tippen auf ein Segment wählt es aus; alles andere
// tritt zurück, und die Mitte beantwortet die Frage zu genau diesem Segment.

import SwiftUI

struct RingSelection: Hashable {
    var direction: Direction
    var categoryID: UUID
}

struct FlowRings<Center: View>: View {
    let summary: MonthSummary
    @Binding var selection: RingSelection?
    @ViewBuilder var center: Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: Double = 0

    // MARK: Maße

    /// Strichstärken: Der äußere Ring ist deutlich kräftiger, damit die beiden Ringe
    /// auch ohne Beschriftung nicht verwechselbar sind.
    private let outerWidth: CGFloat = 20
    private let innerWidth: CGFloat = 11
    private let ringGap: CGFloat = 9

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let geometry = Geometry(
                side: side, outerWidth: outerWidth, innerWidth: innerWidth, ringGap: ringGap)

            ZStack {
                ring(.expense, geometry: geometry)
                ring(.income, geometry: geometry)

                center
                    .frame(width: geometry.innerRadius * 2 - innerWidth - 22)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { location in
                // Die Trefferfläche ist der Ring selbst, nicht der ganze Kreis: Ein
                // Tippen in die Mitte soll die Auswahl aufheben, nicht raten.
                let hit = hit(at: location, in: proxy.size, geometry: geometry)
                withAnimation(motion) { selection = hit == selection ? nil : hit }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task {
            guard reveal == 0 else { return }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.9, bounce: 0.1)) { reveal = 1 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Ein Ring

    @ViewBuilder
    private func ring(_ direction: Direction, geometry: Geometry) -> some View {
        let radius = direction == .expense ? geometry.outerRadius : geometry.innerRadius
        let width = direction == .expense ? outerWidth : innerWidth
        let segments = segments(for: direction)

        ZStack {
            Circle()
                .strokeBorder(Palette.track, lineWidth: width)
                .frame(width: radius * 2 + width, height: radius * 2 + width)

            ForEach(segments) { segment in
                let isSelected = selection?.categoryID == segment.id
                    && selection?.direction == direction

                Arc(start: segment.start * reveal, length: segment.length * reveal, radius: radius)
                    .stroke(
                        Palette.tint(segment.tint),
                        style: StrokeStyle(lineWidth: width, lineCap: segment.cap))
                    .opacity(selection == nil || isSelected ? 1 : 0.18)
                    // Das ausgewählte Segment tritt einen Hauch aus dem Ring heraus,
                    // statt zusätzlich die Farbe zu wechseln.
                    .scaleEffect(isSelected && !reduceMotion ? 1.035 : 1)
                    .shadow(
                        color: isSelected ? Palette.tint(segment.tint).opacity(0.5) : .clear,
                        radius: 10)
            }
        }
        .animation(motion, value: selection)
        .animation(motion, value: summary)
        .accessibilityHidden(true)
    }

    // MARK: Aufteilung

    private struct Segment: Identifiable {
        let id: UUID
        let tint: CategoryTint
        /// In Umdrehungen ab zwölf Uhr, im Uhrzeigersinn.
        let start: Double
        let length: Double
        let cap: CGLineCap
    }

    private func segments(for direction: Direction) -> [Segment] {
        let ring = summary.ring(direction)
        let sweep = summary.sweep(direction)
        guard sweep > 0, !ring.slices.isEmpty else { return [] }

        // Die Lücke zwischen zwei Segmenten ist so breit wie nötig, um die runden
        // Enden voneinander zu trennen — und schrumpft mit, wenn viele kleine
        // Kategorien um denselben Platz konkurrieren.
        let single = ring.slices.count == 1
        let gap = single ? 0 : min(0.012, sweep / Double(ring.slices.count) * 0.22)

        var cursor: Double = 0
        return ring.slices.map { slice in
            let span = sweep * slice.share
            let segment = Segment(
                id: slice.category.id,
                tint: slice.category.tint,
                start: cursor + gap / 2,
                length: max(0.0016, span - gap),
                cap: single && sweep >= 0.999 ? .butt : .round)
            cursor += span
            return segment
        }
    }

    // MARK: Treffer

    private func hit(at point: CGPoint, in size: CGSize, geometry: Geometry) -> RingSelection? {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        let direction: Direction
        if abs(distance - geometry.outerRadius) <= outerWidth / 2 + 8 {
            direction = .expense
        } else if abs(distance - geometry.innerRadius) <= innerWidth / 2 + 8 {
            direction = .income
        } else {
            return nil
        }

        var turns = (atan2(dy, dx) / (2 * .pi)) + 0.25
        if turns < 0 { turns += 1 }

        for segment in segments(for: direction)
        where turns >= segment.start - 0.01 && turns <= segment.start + segment.length + 0.01 {
            return RingSelection(direction: direction, categoryID: segment.id)
        }
        return nil
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.15)
    }

    private var accessibilityLabel: String {
        "Ausgaben \(MoneyFormat.amount(summary.expenses.total)), "
            + "Einnahmen \(MoneyFormat.amount(summary.income.total))"
    }

    private struct Geometry {
        let outerRadius: CGFloat
        let innerRadius: CGFloat

        init(side: CGFloat, outerWidth: CGFloat, innerWidth: CGFloat, ringGap: CGFloat) {
            outerRadius = (side - outerWidth) / 2
            innerRadius = outerRadius - outerWidth / 2 - ringGap - innerWidth / 2
        }
    }
}

/// Ein Kreisbogen, in Umdrehungen ab zwölf Uhr gerechnet, damit die Aufteilung der
/// Ringe ohne Gradrechnerei auskommt.
private struct Arc: Shape {
    var start: Double
    var length: Double
    var radius: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start, length) }
        set { start = newValue.first; length = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(start * 360 - 90),
            endAngle: .degrees((start + length) * 360 - 90),
            clockwise: false)
        return path
    }
}
