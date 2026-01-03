import Foundation
import os

/// Loads and caches Apple's Aerial catalog (`entries.json`).
///
/// Implemented as an `actor` to ensure thread-safe caching of the parsed catalog.
actor AerialCatalog {
    enum CatalogError: LocalizedError {
        case fileNotFound(URL)
        case decodeFailed(URL, underlying: Error)
        case attributesFailed(URL, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "Aerial catalog not found at \(url.path). This file is normally provided by macOS (idleassetsd)."
            case .decodeFailed(let url, let underlying):
                return "Failed to decode Aerial catalog at \(url.path): \(underlying.localizedDescription)"
            case .attributesFailed(let url, let underlying):
                return "Failed to read catalog file attributes at \(url.path): \(underlying.localizedDescription)"
            }
        }
    }

    struct Snapshot: Sendable {
        let assets: [AerialAsset]
        let categories: [AerialCategory]
        let fileURL: URL
        let fileModificationDate: Date?
    }

    private let logger = Logger(subsystem: "com.secondarrow.AerialFlow", category: "AerialCatalog")
    private let fileURL: URL
    private let fileSystem: FileSystem

    private var cached: Snapshot?

    init(
        fileURL: URL = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/entries.json"),
        fileSystem: FileSystem
    ) {
        self.fileURL = fileURL
        self.fileSystem = fileSystem
    }

    func loadSnapshot() throws -> Snapshot {
        guard fileSystem.fileExists(at: fileURL) else {
            throw CatalogError.fileNotFound(fileURL)
        }

        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try fileSystem.attributesOfItem(at: fileURL)
        } catch {
            throw CatalogError.attributesFailed(fileURL, underlying: error)
        }
        let mtime = attrs[.modificationDate] as? Date

        if let cached, cached.fileModificationDate == mtime {
            return cached
        }

        let data: Data
        do {
            data = try fileSystem.readData(from: fileURL)
        } catch {
            throw CatalogError.decodeFailed(fileURL, underlying: error)
        }
        do {
            let decoded = try JSONDecoder().decode(AerialEntries.self, from: data)
            let snapshot = Snapshot(
                assets: decoded.assets.filter { !$0.id.isEmpty },
                categories: decoded.categories.filter { !$0.id.isEmpty },
                fileURL: fileURL,
                fileModificationDate: mtime
            )
            cached = snapshot
            logger.debug("Loaded catalog: assets=\(snapshot.assets.count), categories=\(snapshot.categories.count)")
            return snapshot
        } catch {
            throw CatalogError.decodeFailed(fileURL, underlying: error)
        }
    }
}

// MARK: - Protocol Conformance

extension AerialCatalog: AerialCataloging {}


