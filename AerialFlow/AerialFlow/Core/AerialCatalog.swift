import Foundation
import os

/// Loads and caches Apple's Aerial catalog (`entries.json`).
///
/// Implemented as an `actor` to ensure thread-safe caching of the parsed catalog.
actor AerialCatalog {
    enum CatalogError: LocalizedError {
        case fileNotFound(candidates: [URL])
        case decodeFailed(URL, underlying: Error)
        case attributesFailed(URL, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let candidates):
                let paths = candidates.map(\.path).joined(separator: "\n- ")
                return """
                Aerial catalog (entries.json) not found or not readable. Checked:
                - \(paths)

                Open System Settings > Wallpaper and select Aerials once, then try again.
                """
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

    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "AerialCatalog")
    private let candidateCatalogURLs: [URL]
    private let fileSystem: FileSystem

    private var cached: Snapshot?

    init(fileURL: URL, fileSystem: FileSystem) {
        self.candidateCatalogURLs = [fileURL]
        self.fileSystem = fileSystem
    }

    init(
        fileSystem: FileSystem,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.candidateCatalogURLs = AerialSystemPaths.candidateCatalogURLs(homeDirectoryURL: homeDirectoryURL)
        self.fileSystem = fileSystem
    }

    func loadSnapshot() throws -> Snapshot {
        var attempted: [URL] = []
        var lastTypedError: CatalogError?

        for url in candidateCatalogURLs {
            attempted.append(url)

            guard fileSystem.fileExists(at: url), fileSystem.isReadable(at: url) else {
                continue
            }

            let attrs: [FileAttributeKey: Any]
            do {
                attrs = try fileSystem.attributesOfItem(at: url)
            } catch {
                lastTypedError = CatalogError.attributesFailed(url, underlying: error)
                continue
            }
            let mtime = attrs[.modificationDate] as? Date

            if let cached, cached.fileURL == url, cached.fileModificationDate == mtime {
                return cached
            }

            let data: Data
            do {
                data = try fileSystem.readData(from: url)
            } catch {
                lastTypedError = CatalogError.decodeFailed(url, underlying: error)
                continue
            }

            do {
                let decoded = try JSONDecoder().decode(AerialEntries.self, from: data)
                let snapshot = Snapshot(
                    assets: decoded.assets.filter { !$0.id.isEmpty },
                    categories: decoded.categories.filter { !$0.id.isEmpty },
                    fileURL: url,
                    fileModificationDate: mtime
                )
                cached = snapshot
                logger.debug("Loaded catalog: assets=\(snapshot.assets.count), categories=\(snapshot.categories.count)")
                return snapshot
            } catch {
                lastTypedError = CatalogError.decodeFailed(url, underlying: error)
                continue
            }
        }

        if let lastTypedError {
            throw lastTypedError
        }

        throw CatalogError.fileNotFound(candidates: attempted)
    }
}

// MARK: - Protocol Conformance

extension AerialCatalog: AerialCataloging {}


