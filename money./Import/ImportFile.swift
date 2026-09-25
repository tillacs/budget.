// ImportFile.swift
// budget. — eine geteilte oder geöffnete Datei lesen

import Foundation

nonisolated enum ImportFile {
    enum ReadError: Error, LocalizedError {
        case unreadable
        var errorDescription: String? { "Die Datei lässt sich nicht lesen." }
    }

    /// Liest die Datei als Text. Dateien aus „Dateien" oder dem Teilen-Menü sind
    /// sicherheitsbeschränkt — der Zugriff wird geöffnet und wieder geschlossen.
    static func read(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else { throw ReadError.unreadable }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }
}
