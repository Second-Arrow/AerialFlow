import Foundation
import os

/// Edits the wallpaper store `Index.plist` to apply a chosen Aerial asset ID.
struct WallpaperStoreEditor: Sendable {
    enum EditorError: LocalizedError {
        case indexPlistNotFound(URL)
        case decodeFailed(URL, underlying: Error)
        case encodeFailed(underlying: Error)
        case noProviderNodesFound(provider: String)
        case configDecodeFailed(underlying: Error)
        case configEncodeFailed(underlying: Error)
        case unsupportedPlistShapeForUpsert

        var errorDescription: String? {
            switch self {
            case .indexPlistNotFound(let url):
                return "Wallpaper settings file (Index.plist) not found at \(url.path). Open System Settings > Wallpaper and select Aerials, then try again."
            case .decodeFailed(let url, let underlying):
                return "Failed to decode Index.plist at \(url.path): \(underlying.localizedDescription)"
            case .encodeFailed(let underlying):
                return "Failed to encode updated Index.plist: \(underlying.localizedDescription)"
            case .noProviderNodesFound(let provider):
                return "Aerials aren’t configured for Wallpaper / Screen Saver yet (provider=\(provider)). Open System Settings > Wallpaper and select Aerials, then try again."
            case .configDecodeFailed(let underlying):
                return "Failed to decode embedded Configuration plist: \(underlying.localizedDescription)"
            case .configEncodeFailed(let underlying):
                return "Failed to encode embedded Configuration plist: \(underlying.localizedDescription)"
            case .unsupportedPlistShapeForUpsert:
                return "Index.plist did not match a known safe shape for inserting Aerial provider nodes. Please open System Settings and set Desktop and Screen Saver to Aerials, then try again."
            }
        }
    }

    struct ApplyResult: Sendable, Equatable {
        let updatedProviderNodeCount: Int
        let backupURL: URL
    }

    struct AerialConfigurationStatus: Sendable, Equatable {
        let totalProviderNodes: Int
        let desktopProviderNodes: Int
        let idleProviderNodes: Int
        let issues: Set<AerialConfigurationIssue>

        var isLikelyConfigured: Bool { issues.isEmpty }
    }

    enum AerialConfigurationIssue: Sendable, Hashable {
        case indexPlistMissing
        case noAerialProviderNodes
        case missingDesktopNode
        case missingIdleNode
    }

    struct AerialConfigurationRepairReport: Sendable, Equatable {
        let didUpsertProviderNodes: Bool
        let updatedProviderNodeCount: Int
        let backupURL: URL
    }

    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "WallpaperStoreEditor")
    private let fileSystem: FileSystem
    private let now: @Sendable () -> Date
    private let configPlist: WallpaperStoreConfigurationPlist
    private let backupRetention: WallpaperStoreBackupRetention

    init(fileSystem: FileSystem, now: @escaping @Sendable () -> Date = Date.init) {
        self.fileSystem = fileSystem
        self.now = now
        self.configPlist = WallpaperStoreConfigurationPlist(
            configDecodeFailed: { EditorError.configDecodeFailed(underlying: $0) },
            configEncodeFailed: { EditorError.configEncodeFailed(underlying: $0) }
        )
        self.backupRetention = WallpaperStoreBackupRetention(fileSystem: fileSystem, logger: logger)
    }

    func applyAerialAssetID(
        _ assetID: String,
        indexPlistURL: URL = WallpaperStoreEditor.defaultIndexPlistURL,
        backupRetentionCount: Int = 10
    ) throws -> ApplyResult {
        guard fileSystem.fileExists(at: indexPlistURL) else {
            throw EditorError.indexPlistNotFound(indexPlistURL)
        }

        let original = try fileSystem.readData(from: indexPlistURL)

        let rootAny: Any
        do {
            rootAny = try PropertyListSerialization.propertyList(from: original, options: [], format: nil)
        } catch {
            throw EditorError.decodeFailed(indexPlistURL, underlying: error)
        }

        let provider = "com.apple.wallpaper.choice.aerials"
        let plistEditor = WallpaperStorePlistEditor(
            now: now,
            rewriteConfiguration: { configData, newAssetID in
                try configPlist.rewriteConfiguration(configData, assetID: newAssetID)
            }
        )
        let edited = try plistEditor.edit(root: rootAny, provider: provider, newAssetID: assetID)
        guard edited.updatedCount > 0 else {
            throw EditorError.noProviderNodesFound(provider: provider)
        }

        let updatedData: Data
        do {
            updatedData = try PropertyListSerialization.data(fromPropertyList: edited.root, format: .binary, options: 0)
        } catch {
            throw EditorError.encodeFailed(underlying: error)
        }

        let backupURL = backupRetention.backupURL(for: indexPlistURL, date: now())
        try fileSystem.writeData(original, to: backupURL, options: [.atomic])
        try fileSystem.writeData(updatedData, to: indexPlistURL, options: [.atomic])
        backupRetention.pruneBackupsBestEffort(indexPlistURL: indexPlistURL, keepingMostRecent: backupRetentionCount)

        logger.debug("Applied assetID=\(assetID, privacy: .public) updatedNodes=\(edited.updatedCount)")
        return ApplyResult(updatedProviderNodeCount: edited.updatedCount, backupURL: backupURL)
    }

    func inspectAerialConfiguration(
        indexPlistURL: URL = WallpaperStoreEditor.defaultIndexPlistURL
    ) throws -> AerialConfigurationStatus {
        guard fileSystem.fileExists(at: indexPlistURL) else {
            return AerialConfigurationStatus(
                totalProviderNodes: 0,
                desktopProviderNodes: 0,
                idleProviderNodes: 0,
                issues: [.indexPlistMissing]
            )
        }

        let data = try fileSystem.readData(from: indexPlistURL)
        let rootAny: Any
        do {
            rootAny = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw EditorError.decodeFailed(indexPlistURL, underlying: error)
        }

        let provider = "com.apple.wallpaper.choice.aerials"
        let plistEditor = WallpaperStorePlistEditor(
            now: now,
            rewriteConfiguration: { configData, newAssetID in
                try configPlist.rewriteConfiguration(configData, assetID: newAssetID)
            }
        )
        let stats = plistEditor.scanForProviderNodes(root: rootAny, provider: provider)

        var issues: Set<AerialConfigurationIssue> = []
        if stats.total == 0 {
            issues.insert(.noAerialProviderNodes)
        }

        return AerialConfigurationStatus(
            totalProviderNodes: stats.total,
            desktopProviderNodes: stats.desktop,
            idleProviderNodes: stats.idle,
            issues: issues
        )
    }

    func repairAerialConfiguration(
        desiredAssetID: String,
        indexPlistURL: URL = WallpaperStoreEditor.defaultIndexPlistURL,
        backupRetentionCount: Int = 10
    ) throws -> AerialConfigurationRepairReport {
        let provider = "com.apple.wallpaper.choice.aerials"

        let status = try inspectAerialConfiguration(indexPlistURL: indexPlistURL)
        if status.totalProviderNodes > 0 {
            let apply = try applyAerialAssetID(
                desiredAssetID,
                indexPlistURL: indexPlistURL,
                backupRetentionCount: backupRetentionCount
            )
            return AerialConfigurationRepairReport(
                didUpsertProviderNodes: false,
                updatedProviderNodeCount: apply.updatedProviderNodeCount,
                backupURL: apply.backupURL
            )
        }

        // Upsert provider nodes only when the plist already contains known safe containers.
        guard fileSystem.fileExists(at: indexPlistURL) else {
            throw EditorError.indexPlistNotFound(indexPlistURL)
        }

        let original = try fileSystem.readData(from: indexPlistURL)
        let rootAny: Any
        do {
            rootAny = try PropertyListSerialization.propertyList(from: original, options: [], format: nil)
        } catch {
            throw EditorError.decodeFailed(indexPlistURL, underlying: error)
        }

        let configData = try makeConfigurationData(assetID: desiredAssetID)
        let upsert = try upsertProviderNodesIfPossible(rootAny, provider: provider, configData: configData)
        guard upsert.updatedCount > 0 else {
            throw EditorError.unsupportedPlistShapeForUpsert
        }

        let updatedData: Data
        do {
            updatedData = try PropertyListSerialization.data(fromPropertyList: upsert.root, format: .binary, options: 0)
        } catch {
            throw EditorError.encodeFailed(underlying: error)
        }

        let backupURL = backupRetention.backupURL(for: indexPlistURL, date: now())
        try fileSystem.writeData(original, to: backupURL, options: [.atomic])
        try fileSystem.writeData(updatedData, to: indexPlistURL, options: [.atomic])
        backupRetention.pruneBackupsBestEffort(indexPlistURL: indexPlistURL, keepingMostRecent: backupRetentionCount)

        logger.debug("Upserted provider nodes updatedCount=\(upsert.updatedCount)")
        return AerialConfigurationRepairReport(
            didUpsertProviderNodes: true,
            updatedProviderNodeCount: upsert.updatedCount,
            backupURL: backupURL
        )
    }

    static var defaultIndexPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("Store", isDirectory: true)
            .appendingPathComponent("Index.plist", isDirectory: false)
    }
    private func makeConfigurationData(assetID: String) throws -> Data {
        try configPlist.makeConfigurationData(assetID: assetID)
    }

    private struct UpsertResult {
        let root: Any
        let updatedCount: Int
    }

    private func upsertProviderNodesIfPossible(_ rootAny: Any, provider: String, configData: Data) throws -> UpsertResult {
        guard var root = rootAny as? [String: Any] else {
            return UpsertResult(root: rootAny, updatedCount: 0)
        }

        var updatedCount = 0

        updatedCount += upsertProviderNode(
            inSectionNamed: "Desktop",
            root: &root,
            provider: provider,
            configData: configData
        )
        updatedCount += upsertProviderNode(
            inSectionNamed: "Idle",
            root: &root,
            provider: provider,
            configData: configData
        )

        return UpsertResult(root: root, updatedCount: updatedCount)
    }

    private func upsertProviderNode(
        inSectionNamed sectionName: String,
        root: inout [String: Any],
        provider: String,
        configData: Data
    ) -> Int {
        guard var section = root[sectionName] as? [String: Any] else { return 0 }
        let didTouchTimestamps: Bool

        if var choice = section["Choice"] as? [String: Any] {
            choice["Provider"] = provider
            choice["Configuration"] = configData
            section["Choice"] = choice
            didTouchTimestamps = true
            root[sectionName] = section
        } else if var nodes = section["Nodes"] as? [Any],
                  var node0 = nodes.first as? [String: Any] {
            node0["Provider"] = provider
            node0["Configuration"] = configData
            nodes[0] = node0
            section["Nodes"] = nodes
            didTouchTimestamps = true
            root[sectionName] = section
        } else {
            return 0
        }

        if didTouchTimestamps {
            if section["LastSet"] != nil { section["LastSet"] = now() }
            if section["LastUse"] != nil { section["LastUse"] = now() }
            root[sectionName] = section
        }

        return 1
    }

}

// MARK: - Protocol Conformance

extension WallpaperStoreEditor: WallpaperApplying {}


