// LaunchWordmark.swift
// budget. — Startanimation der Wortmarke
//
// Der Punkt ist das Markenzeichen: Er zeichnet sich beim Start erst als
// Fortschrittsring, schnappt dann zum Punkt zusammen — und erst danach
// schiebt sich das Wort davor. Die Proportionen (Punkt-Ø = 0,32 × Schriftgrad,
// Lücke = 0,145 × Schriftgrad) sind identisch zum App-Icon, damit der Übergang
// vom Homescreen in die App nahtlos wirkt.

import SwiftUI
import UIKit

// MARK: - Gemeinsame Maße

enum Wordmark {
    /// Punkt-Durchmesser im Verhältnis zum Schriftgrad (aus dem Icon übernommen)
    static let dotRatio: CGFloat = 0.320
    /// Abstand Wort ↔ Punkt im Verhältnis zum Schriftgrad
    static let gapRatio: CGFloat = 0.145
    /// Ring beim Start — Vielfaches des Punkt-Durchmessers
    static let ringRatio: CGFloat = 2.6

    /// Charter Bold, mit Rückfall auf die System-Serife, falls nicht vorhanden.
    static func font(size: CGFloat) -> Font {
        if UIFont(name: "Charter-Bold", size: size) != nil {
            return .custom("Charter-Bold", size: size)
        }
        return .system(size: size, weight: .bold, design: .serif)
    }
}

private struct WordmarkWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Startanimation

struct LaunchWordmark: View {
    /// Titel OHNE Punkt, z. B. „progress"
    let stem: String
    var fontSize: CGFloat = 46
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var ringTrim: CGFloat = 0
    @State private var ringCollapsed = false
    @State private var dotScale: CGFloat = 0
    @State private var textRevealed = false
    @State private var opacity: Double = 1
    @State private var textWidth: CGFloat = 0

    private var ink: Color { colorScheme == .dark ? .white : .black }
    private var paper: Color { colorScheme == .dark ? .black : .white }

    private var dotD: CGFloat { fontSize * Wordmark.dotRatio }
    private var gap: CGFloat { fontSize * Wordmark.gapRatio }
    private var ringD: CGFloat { dotD * Wordmark.ringRatio }

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()

            // Grundlinien-Ausrichtung: der Punkt sitzt AUF der Schriftlinie,
            // exakt wie im App-Icon — nicht mittig zur Zeilenhöhe.
            HStack(alignment: .firstTextBaseline, spacing: gap) {
                Text(stem)
                    .font(Wordmark.font(size: fontSize))
                    .foregroundStyle(ink)
                    .fixedSize()
                    .background {
                        GeometryReader { g in
                            Color.clear.preference(key: WordmarkWidthKey.self, value: g.size.width)
                        }
                    }
                    .opacity(textRevealed ? 1 : 0)
                    .blur(radius: textRevealed ? 0 : 5)

                dot
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }
            }
            // Solange das Wort unsichtbar ist, sitzt der Punkt exakt in der
            // Bildmitte; beim Einblenden rutscht die Wortmarke in ihre Endlage.
            .offset(x: textRevealed ? 0 : -(textWidth + gap) / 2)
        }
        .opacity(opacity)
        .onPreferenceChange(WordmarkWidthKey.self) { textWidth = $0 }
        .task { await play() }
        .accessibilityElement()
        .accessibilityLabel("\(stem).")
    }

    private var dot: some View {
        Circle()
            .fill(ink)
            .frame(width: dotD, height: dotD)
            .scaleEffect(dotScale)
            // Der Ring liegt als Overlay auf dem Punkt — so beeinflusst seine
            // Größe das Layout nicht, und die Wortmarke springt nicht.
            .overlay {
                Circle()
                    .trim(from: 0, to: ringTrim)
                    .stroke(ink, style: StrokeStyle(lineWidth: dotD * 0.42, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringD, height: ringD)
                    .scaleEffect(ringCollapsed ? dotD / ringD : 1)
                    .opacity(ringCollapsed ? 0 : 1)
            }
    }

    @MainActor
    private func play() async {
        guard !reduceMotion else {
            // Ohne Bewegung: fertige Wortmarke zeigen, nur weich ausblenden.
            ringTrim = 1
            ringCollapsed = true
            dotScale = 1
            textRevealed = true
            try? await Task.sleep(for: .seconds(0.55))
            withAnimation(.easeOut(duration: 0.3)) { opacity = 0 }
            try? await Task.sleep(for: .seconds(0.3))
            onFinished()
            return
        }

        withAnimation(.easeInOut(duration: 0.55)) { ringTrim = 1 }
        try? await Task.sleep(for: .seconds(0.55))

        // Ring fällt in den Punkt zusammen
        withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
            ringCollapsed = true
            dotScale = 1
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        try? await Task.sleep(for: .seconds(0.14))

        withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) { textRevealed = true }
        try? await Task.sleep(for: .seconds(0.5))

        withAnimation(.easeOut(duration: 0.3)) { opacity = 0 }
        try? await Task.sleep(for: .seconds(0.3))
        onFinished()
    }
}

#Preview {
    LaunchWordmark(stem: "budget") {}
}
