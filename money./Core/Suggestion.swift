// Suggestion.swift
// budget. — was die Maschine zu einer Buchung meint
//
// Ein Vorschlag ist eine Kategorie mit einer Konfidenz und einer Liste von Gründen.
// Die Gründe sind keine Debug-Ausgabe, sondern Oberfläche: Jede Zeile im Posteingang
// sagt in einem Satz, warum sie so vorgeschlagen wurde.

import Foundation

nonisolated enum EvidenceKind: String, Codable, Hashable, Sendable {
    case merchant, iban, recurring, token, mccLearned, mccPrior, type, isin, lastUsed, refund
}

nonisolated struct Evidence: Codable, Hashable, Sendable {
    let kind: EvidenceKind
    /// Ein Satzstück, das sich hinter „weil" lesen lässt: „EDEKA 7× so gebucht".
    let text: String
    let strength: Double
}

nonisolated enum Decision: Codable, Hashable, Sendable {
    case accepted
    case corrected(UUID)
    case rejected
}

nonisolated struct Suggestion: Codable, Hashable, Sendable {
    var categoryID: UUID
    /// 0…1. Unter 0,6 fragt die App offen, ab der Automatik-Schwelle bucht sie selbst.
    var confidence: Double
    /// Die nächstbesten, für die Chips im Posteingang. Ohne die erste.
    var alternatives: [UUID]
    var evidence: [Evidence]
    var decision: Decision?

    init(
        categoryID: UUID, confidence: Double, alternatives: [UUID] = [],
        evidence: [Evidence] = [], decision: Decision? = nil
    ) {
        self.categoryID = categoryID
        self.confidence = confidence
        self.alternatives = alternatives
        self.evidence = evidence
        self.decision = decision
    }

    /// Ein Vorschlag ohne einen einzigen Grund: reiner Rückfall auf die erste
    /// Kategorie. Die Oberfläche zeigt dann „Wofür?" statt einer Kategorie.
    var isGuess: Bool { evidence.isEmpty }

    /// Die Begründung in einer Zeile.
    var reason: String {
        let parts = evidence.sorted { $0.strength > $1.strength }.prefix(2).map(\.text)
        return parts.joined(separator: " · ")
    }

    /// Drei Stufen für die Oberfläche: sicher, wahrscheinlich, unsicher.
    var band: ConfidenceBand {
        if confidence >= 0.9 { return .sure }
        if confidence >= 0.6 { return .likely }
        return .unsure
    }
}

nonisolated enum ConfidenceBand: Hashable, Sendable {
    case sure, likely, unsure
}
