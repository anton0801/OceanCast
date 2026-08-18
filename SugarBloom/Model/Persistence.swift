//
//  Persistence.swift
//  Ocean Cast
//
//  Local JSON store. Everything survives a restart; a damaged file is never
//  silently replaced — it is copied aside and reported.
//

import Foundation

enum PersistenceError: LocalizedError {
    case corruptFile(backup: URL?, underlying: String)
    case writeFailed(String)
    case invalidBackup(String)

    var errorDescription: String? {
        switch self {
        case .corruptFile(let backup, let underlying):
            let where_ = backup.map { " A copy was kept at \($0.lastPathComponent)." } ?? ""
            return "The saved file could not be read.\(where_) (\(underlying))"
        case .writeFailed(let message):
            return "Changes could not be written to disk. (\(message))"
        case .invalidBackup(let message):
            return "This backup file is not valid Ocean Cast data. (\(message))"
        }
    }
}

final class PersistenceController {
    static let shared = PersistenceController()

    let directory: URL
    let dataURL: URL
    let photosDirectory: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? URL.temporaryDirectory
        directory = base.appendingPathComponent("OceanCast", isDirectory: true)

        // The app used to store its data under a different folder name. Move it
        // once, so renaming the product never costs anybody their kitchen.
        let legacy = base.appendingPathComponent("SugarBloom", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: directory)
        }

        dataURL = directory.appendingPathComponent("data.json")
        photosDirectory = directory.appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Load / save

    func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: dataURL.path) else { return AppData() }
        let raw = try Data(contentsOf: dataURL)
        do {
            return try decoder.decode(AppData.self, from: raw)
        } catch {
            let backup = directory.appendingPathComponent("data-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? raw.write(to: backup)
            throw PersistenceError.corruptFile(backup: backup, underlying: error.localizedDescription)
        }
    }

    func save(_ data: AppData) throws {
        do {
            var copy = data
            copy.savedAt = Date()
            let encoded = try encoder.encode(copy)
            let temporary = dataURL.appendingPathExtension("tmp")
            try encoded.write(to: temporary, options: .atomic)
            _ = try FileManager.default.replaceItemAt(dataURL, withItemAt: temporary)
        } catch {
            throw PersistenceError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Export / import

    func exportJSON(_ data: AppData) throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent("OceanCast-backup-\(fileStamp()).json")
        try encoder.encode(data).write(to: url, options: .atomic)
        return url
    }

    func exportCSV(_ text: String, name: String) throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent("OceanCast-\(name)-\(fileStamp()).csv")
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    /// Decodes a backup without touching the live store, so the user can see
    /// what it contains before replacing anything.
    func inspectBackup(at url: URL) throws -> AppData {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        do {
            let raw = try Data(contentsOf: url)
            let decoded = try decoder.decode(AppData.self, from: raw)
            guard decoded.schemaVersion >= 1 else {
                throw PersistenceError.invalidBackup("unsupported schema version \(decoded.schemaVersion)")
            }
            return decoded
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.invalidBackup(error.localizedDescription)
        }
    }

    /// Keeps the current file aside before an import replaces it.
    func snapshotBeforeImport() {
        guard FileManager.default.fileExists(atPath: dataURL.path) else { return }
        let backup = directory.appendingPathComponent("data-before-import-\(fileStamp()).json")
        try? FileManager.default.copyItem(at: dataURL, to: backup)
    }

    // MARK: - Photos

    func savePhoto(_ data: Data) throws -> String {
        let name = "photo-\(UUID().uuidString).jpg"
        try data.write(to: photosDirectory.appendingPathComponent(name), options: .atomic)
        return name
    }

    func photoURL(_ name: String) -> URL {
        photosDirectory.appendingPathComponent(name)
    }

    func photoData(_ name: String?) -> Data? {
        guard let name else { return nil }
        return try? Data(contentsOf: photoURL(name))
    }

    func deletePhoto(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: photoURL(name))
    }

    func eraseEverything() {
        try? FileManager.default.removeItem(at: dataURL)
        try? FileManager.default.removeItem(at: photosDirectory)
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
    }

    private func fileStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }
}
