// QuickEntryRouter.swift
// budget. — die Brücke vom Kurzbefehl in die Oberfläche
//
// Der Kurzbefehl (und damit der Doppeltipp auf die Rückseite) startet die App und
// legt hier ab, was erfasst werden soll. Die eine Seite hört darauf und schiebt den
// Ziffernblock hoch — auch aus dem Kaltstart heraus, weil die Anforderung stehen
// bleibt, bis sie jemand abholt.

import Foundation
import Observation

@MainActor
@Observable
final class QuickEntryRouter {
    static let shared = QuickEntryRouter()

    private(set) var pending: Direction?

    /// Zählt jede Anforderung mit. Ohne diesen Zähler bliebe ein zweiter Doppeltipp
    /// derselben Richtung folgenlos, weil sich `pending` nicht geändert hätte.
    private(set) var token = 0

    func request(_ direction: Direction) {
        pending = direction
        token += 1
    }

    /// Von der Oberfläche aufgerufen, sobald der Ziffernblock offen ist.
    func consume() -> Direction? {
        defer { pending = nil }
        return pending
    }
}
