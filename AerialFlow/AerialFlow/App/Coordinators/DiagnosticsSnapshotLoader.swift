import Foundation

/// Builds `DiagnosticsSnapshot` from current settings + stores.
struct DiagnosticsSnapshotLoader: Sendable {
    private let fileSystem: any FileSystem
    private let directoryDetector: ActiveVideoDirectoryDetector
    private let stateStore: any AerialEngineStateStore
    private let nextScheduledChangeDate: @Sendable () async -> Date?

    init(
        fileSystem: any FileSystem,
        directoryDetector: ActiveVideoDirectoryDetector,
        stateStore: any AerialEngineStateStore,
        nextScheduledChangeDate: @escaping @Sendable () async -> Date?
    ) {
        self.fileSystem = fileSystem
        self.directoryDetector = directoryDetector
        self.stateStore = stateStore
        self.nextScheduledChangeDate = nextScheduledChangeDate
    }

    func load(settings: AppSettings) async throws -> DiagnosticsSnapshot {
        let indexPlistURL = settings.indexPlistURL

        async let lastAssetID = stateStore.getLastAssetID()
        async let lastChange = stateStore.getLastChange()
        async let nextScheduledChangeDate = nextScheduledChangeDate()

        let detection = try directoryDetector.detect()
        let backups = Self.findIndexPlistBackups(fileSystem: fileSystem, indexPlistURL: indexPlistURL)
        let recentNames = backups.prefix(5).map(\.lastPathComponent)
        let storageUsedBytes = Self.calculateStorageUsed(fileSystem: fileSystem, videoDirectory: detection.videoDirectory)
        let indexPlistShapeDescription = Self.detectIndexPlistShapeDescription(fileSystem: fileSystem, indexPlistURL: indexPlistURL)

        let resolvedLastAssetID = await lastAssetID

        let currentMovPath = detection.currentMovPath ?? Self.fallbackMovPath(
            fileSystem: fileSystem,
            videoDirectory: detection.videoDirectory,
            lastAssetID: resolvedLastAssetID
        )

        return DiagnosticsSnapshot(
            detectedVideoDirectory: detection.videoDirectory,
            currentMovPath: currentMovPath,
            lastAssetID: resolvedLastAssetID,
            lastChange: await lastChange,
            nextScheduledChangeDate: await nextScheduledChangeDate,
            backupCount: backups.count,
            recentBackupFileNames: recentNames,
            storageUsedBytes: storageUsedBytes,
            indexPlistShapeDescription: indexPlistShapeDescription
        )
    }

    // MARK: - Helpers (pure / easily testable)

    static func findIndexPlistBackups(fileSystem: any FileSystem, indexPlistURL: URL) -> [URL] {
        let dir = indexPlistURL.deletingLastPathComponent()
        let prefix = "\(indexPlistURL.lastPathComponent)."

        let files: [URL]
        do {
            files = try fileSystem.listFiles(in: dir)
        } catch {
            return []
        }

        // Backups are named like: Index.plist.YYYYMMDD-HHmmss.bak
        let backups = files.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix(prefix) && name.hasSuffix(".bak")
        }

        // Timestamp format sorts lexicographically, so name-desc gives newest-first.
        return backups.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func fallbackMovPath(fileSystem: any FileSystem, videoDirectory: URL, lastAssetID: String?) -> URL? {
        guard let assetID = lastAssetID, !assetID.isEmpty else { return nil }
        let movPath = videoDirectory.appendingPathComponent("\(assetID).mov")
        guard fileSystem.fileExists(at: movPath) else { return nil }
        return movPath
    }

    static func calculateStorageUsed(fileSystem: any FileSystem, videoDirectory: URL) -> Int64? {
        guard fileSystem.fileExists(at: videoDirectory) else {
            return nil
        }

        let files: [URL]
        do {
            files = try fileSystem.listFiles(in: videoDirectory)
        } catch {
            return nil
        }

        // Filter for .mov files, excluding hidden files (starting with .). `.part` files are hidden by design.
        let movFiles = files.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".mov") && !name.hasPrefix(".")
        }

        var totalBytes: Int64 = 0
        for file in movFiles {
            do {
                let size = try fileSystem.fileSize(at: file)
                totalBytes += size
            } catch {
                continue
            }
        }

        return totalBytes
    }

    static func detectIndexPlistShapeDescription(fileSystem: any FileSystem, indexPlistURL: URL) -> String? {
        guard fileSystem.fileExists(at: indexPlistURL) else { return nil }
        let data: Data
        do {
            data = try fileSystem.readData(from: indexPlistURL)
        } catch {
            return nil
        }

        let rootAny: Any
        do {
            rootAny = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            return nil
        }

        return WallpaperStoreIndexPlistShape.summarize(root: rootAny).description
    }
}

