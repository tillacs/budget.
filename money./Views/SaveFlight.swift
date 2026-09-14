// SaveFlight.swift
// budget. — die Bestätigung, die nach oben verschwindet
//
// Nach dem Sichern löst sich der Betrag von der Seite, schrumpft und fährt in die
// Dynamic Island — dorthin, wo das iPhone selbst seine Bestätigungen ablegt. Das
// ersetzt eine Meldung, die man wegtippen müsste: Man sieht, dass die Buchung
// angekommen ist, und die Seite dahinter zeigt schon das neue Ergebnis.

import SwiftUI

struct SaveFlight: View {
    let text: String
    let tint: Color
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var swallowed = false

    /// Mitte der Dynamic Island, vom oberen Bildschirmrand aus. Auf Geräten mit Kerbe
    /// sitzt dort dasselbe schwarze Feld — die Bewegung stimmt also auch da.
    private let islandCenterY: CGFloat = 29

    var body: some View {
        GeometryReader { proxy in
            pill
                .scaleEffect(scale)
                .opacity(opacity)
                .position(
                    x: proxy.size.width / 2,
                    y: swallowed ? islandCenterY : proxy.size.height * 0.42)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task { await play() }
    }

    private var pill: some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .background(
                Capsule()
                    .fill(Palette.card)
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 8))
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }

    private var scale: CGFloat {
        if swallowed { return 0.08 }
        return appeared ? 1 : 0.7
    }

    private var opacity: Double {
        if swallowed { return 0 }
        return appeared ? 1 : 0
    }

    @MainActor
    private func play() async {
        guard !reduceMotion else {
            appeared = true
            try? await Task.sleep(for: .seconds(0.7))
            onFinished()
            return
        }

        withAnimation(.spring(duration: 0.26, bounce: 0.4)) { appeared = true }
        try? await Task.sleep(for: .seconds(0.42))

        // Hineinfahren ist schneller als Erscheinen und läuft am Ende aus — so wirkt
        // es, als hätte die Insel den Betrag geschluckt, nicht als wäre er verblasst.
        withAnimation(.timingCurve(0.34, 0, 0.2, 1, duration: 0.5)) { swallowed = true }
        try? await Task.sleep(for: .seconds(0.5))
        onFinished()
    }
}
