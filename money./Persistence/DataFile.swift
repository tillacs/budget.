// DataFile.swift
// budget. — eine JSON-Datei. Kein Netz, kein geteilter Container, kein iCloud.

import Foundation

/// Der Ort ist eine Eigenschaft und keine Konstante, damit Tests ihre eigene Datei
/// bekommen, statt sich um die der App zu streiten.
nonisolated struct DataFile: Sendable {
    let fileURL: URL

    static let applicationDefault: DataFile = {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return DataFile(
            fileURL: base
                .appendingPathComponent("money", isDirectory: true)
                .appendingPathComponent("data.json", isDirectory: false))
    }()

    func load() throws -> AppData? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(AppData.self, from: Data(contentsOf: fileURL))
    }

    func save(_ data: AppData) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Atomar, damit ein abgebrochener Schreibvorgang keine halbe Datei hinterlässt.
        try encoder.encode(data).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
