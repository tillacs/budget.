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

    /// Strichstärken: Der äußere Ring ist deutlich kräftiger. Das trennt die beiden
    /// Ringe nicht nur voneinander — es setzt auch die Rangfolge. Die Ausgaben sind
    /// das, worum es in dieser App geht; die Einnahmen sind der Maßstab dazu.
    private let outerWidth: CGFloat = 23
    private let innerWidth: CGFloat = 9
    private let ringGap: CGFloat = 10
    /// Der sichtbare Abstand zwischen zwei Segmenten, in Punkten.
    private let segmentGap: CGFloat = 4

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

        ZStack {
            Circle()
                .strokeBorder(Palette.track, lineWidth: width)
                .frame(width: radius * 2 + width, height: radius * 2 + width)

            ForEach(segments(for: direction, radius: radius, width: width)) { segment in
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

    private func segments(
        for direction: Direction, radius: CGFloat, width: CGFloat
    ) -> [Segment] {
        let ring = summary.ring(direction)
        let sweep = summary.sweep(direction)
        guard sweep > 0, !ring.slices.isEmpty else { return [] }

        // Ein einzelnes Segment über den ganzen Kreis schließt mit stumpfen Enden
        // sauber zusammen; eine Lücke hätte dort keinen Gegenüber.
        if ring.slices.count == 1, sweep >= 0.999 {
            let slice = ring.slices[0]
            return [Segment(
                id: slice.category.id, tint: slice.category.tint,
                start: 0, length: 1, cap: .butt)]
        }

        // Ein rundes Ende ragt eine halbe Strichstärke über den Bogen hinaus. Eine
        // Lücke muss diesen Überstand erst abtragen, bevor überhaupt Abstand
        // entsteht — sonst schieben sich benachbarte Segmente übereinander.
        let circumference = 2 * .pi * radius
        let capOverhang = Double(width / 2 / circumference)
        let breathing = ring.slices.count == 1 ? 0 : Double(segmentGap / circumference)
        let dot = Double(1.5 / circumference)

        var gap = 2 * capOverhang + breathing
        // Weniger als diesen Bogen kann ein Segment nicht einnehmen, ohne unsichtbar
        // zu werden: Was übrig bleibt, wäre kürzer als sein eigenes rundes Ende.
        var minimumSpan = gap + dot

        // Passen die Mindestbreiten nicht in den Ring, wird zuerst die Luft zwischen
        // den Segmenten zurückgenommen — lieber eng als lückenhaft.
        let count = Double(ring.slices.count)
        if minimumSpan * count > sweep {
            minimumSpan = sweep / count
            gap = max(0, minimumSpan - dot)
        }

        // Kategorien unter der Mindestbreite bekommen sie, und was dafür fehlt, wird
        // den größeren anteilig abgezogen.
        //
        // Das verschiebt die Proportionen um wenige Zehntel Prozent — der Preis
        // dafür, dass eine Kategorie mit 2 % nicht einfach aus dem Bild fällt. Die
        // genauen Anteile stehen ohnehin in der Liste darunter.
        var spans = ring.slices.map { sweep * $0.share }
        let deficit = spans.reduce(0) { $0 + max(0, minimumSpan - $1) }
        if deficit > 0 {
            let surplus = spans.reduce(0) { $0 + max(0, $1 - minimumSpan) }
            if surplus > 0 {
                let factor = min(1, deficit / surplus)
                spans = spans.map {
                    $0 > minimumSpan ? $0 - ($0 - minimumSpan) * factor : minimumSpan
                }
            }
        }

        var cursor: Double = 0
        return zip(ring.slices, spans).map { slice, span in
            let segment = Segment(
                id: slice.category.id,
                tint: slice.category.tint,
                start: cursor + gap / 2,
                // Bleibt nichts übrig, wird daraus ein Punkt — das runde Ende allein.
                length: max(dot, span - gap),
                cap: .round)
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

        let radius = direction == .expense ? geometry.outerRadius : geometry.innerRadius
        let width = direction == .expense ? outerWidth : innerWidth
        for segment in segments(for: direction, radius: radius, width: width)
        where turns >= segment.start - 0.02 && turns <= segment.start + segment.length + 0.02 {
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
