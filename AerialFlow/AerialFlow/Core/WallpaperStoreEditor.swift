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

    init(fileSystem: FileSystem, now: @escaping @Sendable () -> Date = Date.init) {
        self.fileSystem = fileSystem
        self.now = now
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
        let edited = try edit(root: rootAny, provider: provider, newAssetID: assetID)
        guard edited.updatedCount > 0 else {
            throw EditorError.noProviderNodesFound(provider: provider)
        }

        let updatedData: Data
        do {
            updatedData = try PropertyListSerialization.data(fromPropertyList: edited.root, format: .binary, options: 0)
        } catch {
            throw EditorError.encodeFailed(underlying: error)
        }

        let backupURL = backupURL(for: indexPlistURL, date: now())
        try fileSystem.writeData(original, to: backupURL, options: [.atomic])
        try fileSystem.writeData(updatedData, to: indexPlistURL, options: [.atomic])
        pruneBackupsBestEffort(indexPlistURL: indexPlistURL, keepingMostRecent: backupRetentionCount)

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
        let stats = scanForProviderNodes(rootAny, provider: provider, path: [])

        var issues: Set<AerialConfigurationIssue> = []
        if stats.total == 0 {
            issues.insert(.noAerialProviderNodes)
        } else {
            if stats.desktop == 0 { issues.insert(.missingDesktopNode) }
            if stats.idle == 0 { issues.insert(.missingIdleNode) }
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

        let backupURL = backupURL(for: indexPlistURL, date: now())
        try fileSystem.writeData(original, to: backupURL, options: [.atomic])
        try fileSystem.writeData(updatedData, to: indexPlistURL, options: [.atomic])
        pruneBackupsBestEffort(indexPlistURL: indexPlistURL, keepingMostRecent: backupRetentionCount)

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

    private struct EditResult {
        let root: Any
        let updatedCount: Int
    }

    private struct ProviderNodeStats {
        var total: Int = 0
        var desktop: Int = 0
        var idle: Int = 0
    }

    private func edit(root: Any, provider: String, newAssetID: String) throws -> EditResult {
        let (node, updatedCount, _) = try editNode(root, path: [], provider: provider, newAssetID: newAssetID)
        return EditResult(root: node, updatedCount: updatedCount)
    }

    /// Returns: (editedNode, updatedProviderCount, didUpdateProviderInSubtree)
    private func editNode(
        _ node: Any,
        path: [String],
        provider: String,
        newAssetID: String
    ) throws -> (Any, Int, Bool) {
        if var dict = node as? [String: Any] {
            var updatedCount = 0
            var didUpdateInSubtree = false

            // Recurse children first (so parent can decide to "touch" timestamps if any update happened).
            for (key, value) in dict {
                if value is [String: Any] || value is [Any] {
                    let (editedChild, childCount, childDidUpdate) = try editNode(
                        value,
                        path: path + [key],
                        provider: provider,
                        newAssetID: newAssetID
                    )
                    dict[key] = editedChild
                    updatedCount += childCount
                    didUpdateInSubtree = didUpdateInSubtree || childDidUpdate
                }
            }

            // Then process this node.
            if let providerValue = dict["Provider"] as? String, providerValue == provider,
               let configData = dict["Configuration"] as? Data {
                let newConfigData = try rewriteConfiguration(configData, assetID: newAssetID)
                dict["Configuration"] = newConfigData
                updatedCount += 1
                didUpdateInSubtree = true
            }

            if didUpdateInSubtree, shouldTouchTimestamps(path: path) {
                if dict["LastSet"] != nil { dict["LastSet"] = now() }
                if dict["LastUse"] != nil { dict["LastUse"] = now() }
            }

            return (dict, updatedCount, didUpdateInSubtree)
        }

        if let array = node as? [Any] {
            var editedArray: [Any] = []
            editedArray.reserveCapacity(array.count)

            var updatedCount = 0
            var didUpdateInSubtree = false

            for value in array {
                if value is [String: Any] || value is [Any] {
                    let (editedChild, childCount, childDidUpdate) = try editNode(
                        value,
                        path: path,
                        provider: provider,
                        newAssetID: newAssetID
                    )
                    editedArray.append(editedChild)
                    updatedCount += childCount
                    didUpdateInSubtree = didUpdateInSubtree || childDidUpdate
                } else {
                    editedArray.append(value)
                }
            }
            return (editedArray, updatedCount, didUpdateInSubtree)
        }

        return (node, 0, false)
    }

    private func rewriteConfiguration(_ data: Data, assetID: String) throws -> Data {
        let cfgAny: Any
        do {
            cfgAny = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw EditorError.configDecodeFailed(underlying: error)
        }

        guard var cfg = cfgAny as? [String: Any] else {
            throw EditorError.configDecodeFailed(underlying: NSError(domain: "AerialFlow", code: 1))
        }
        cfg["assetID"] = assetID

        do {
            return try PropertyListSerialization.data(fromPropertyList: cfg, format: .binary, options: 0)
        } catch {
            throw EditorError.configEncodeFailed(underlying: error)
        }
    }

    private func makeConfigurationData(assetID: String) throws -> Data {
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: ["assetID": assetID],
                format: .binary,
                options: 0
            )
        } catch {
            throw EditorError.configEncodeFailed(underlying: error)
        }
    }

    private func scanForProviderNodes(_ node: Any, provider: String, path: [String]) -> ProviderNodeStats {
        if let dict = node as? [String: Any] {
            var stats = ProviderNodeStats()

            if let providerValue = dict["Provider"] as? String, providerValue == provider,
               dict["Configuration"] is Data {
                stats.total += 1
                if path.contains("Desktop") { stats.desktop += 1 }
                if path.contains("Idle") { stats.idle += 1 }
            }

            for (key, value) in dict {
                if value is [String: Any] || value is [Any] {
                    let child = scanForProviderNodes(value, provider: provider, path: path + [key])
                    stats.total += child.total
                    stats.desktop += child.desktop
                    stats.idle += child.idle
                }
            }
            return stats
        }

        if let array = node as? [Any] {
            var stats = ProviderNodeStats()
            for value in array {
                if value is [String: Any] || value is [Any] {
                    let child = scanForProviderNodes(value, provider: provider, path: path)
                    stats.total += child.total
                    stats.desktop += child.desktop
                    stats.idle += child.idle
                }
            }
            return stats
        }

        return ProviderNodeStats()
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

    private func shouldTouchTimestamps(path: [String]) -> Bool {
        path.contains("Desktop") || path.contains("Idle")
    }

    private func backupURL(for indexPlistURL: URL, date: Date) -> URL {
        let stamp = Self.timestampString(for: date)
        let dir = indexPlistURL.deletingLastPathComponent()
        let name = "\(indexPlistURL.lastPathComponent).\(stamp).bak"
        return dir.appendingPathComponent(name)
    }

    private func pruneBackupsBestEffort(indexPlistURL: URL, keepingMostRecent count: Int) {
        let keepCount = max(1, count)
        let dir = indexPlistURL.deletingLastPathComponent()
        let prefix = "\(indexPlistURL.lastPathComponent)."

        let files: [URL]
        do {
            files = try fileSystem.listFiles(in: dir)
        } catch {
            logger.debug("Backup retention: could not list backups in \(dir.path, privacy: .public)")
            return
        }

        let backups = files
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix(prefix) && name.hasSuffix(".bak")
            }
            // Name sorts by timestamp (yyyyMMdd-HHmmss), so descending keeps newest first.
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard backups.count > keepCount else { return }

        for url in backups.dropFirst(keepCount) {
            do {
                try fileSystem.removeItem(at: url)
            } catch {
                logger.debug("Backup retention: failed to remove \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static let timestampFormatterLock = NSLock()
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func timestampString(for date: Date) -> String {
        timestampFormatterLock.lock()
        defer { timestampFormatterLock.unlock() }
        return timestampFormatter.string(from: date)
    }
}

// MARK: - Protocol Conformance

extension WallpaperStoreEditor: WallpaperApplying {}


