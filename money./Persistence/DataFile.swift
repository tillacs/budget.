import Foundation

nonisolated enum DataFileError: LocalizedError {
    case unreadableEncoding

    var errorDescription: String? {
        switch self {
        case .unreadableEncoding:
            return "Die Datei ist weder UTF-8 noch ISO-8859-1 und kann nicht gelesen werden."
        }
    }
}

/// One JSON file. No network, no shared container, no iCloud.
///
/// The location is a property rather than a constant so tests get their own file instead of
/// racing each other over the app's.
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
        // Atomic, so an interrupted write cannot leave half a ledger behind.
        try encoder.encode(data).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Trade Republic writes UTF-8, but a file that has been through Excel often comes back
    /// as Latin-1 with the umlauts intact.
    static func readText(at url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw DataFileError.unreadableEncoding
    }
}
