import Foundation

/// Focused helpers for traversing and editing the wallpaper store plist tree.
///
/// This is intentionally independent from file IO so it can be unit-tested in isolation.
struct WallpaperStorePlistEditor: Sendable {
    struct EditResult {
        let root: Any
        let updatedCount: Int
    }

    struct ProviderNodeStats: Sendable, Equatable {
        var total: Int = 0
        var desktop: Int = 0
        var idle: Int = 0
    }

    private let now: @Sendable () -> Date
    private let rewriteConfiguration: @Sendable (_ configurationData: Data, _ newAssetID: String) throws -> Data

    init(
        now: @escaping @Sendable () -> Date,
        rewriteConfiguration: @escaping @Sendable (_ configurationData: Data, _ newAssetID: String) throws -> Data
    ) {
        self.now = now
        self.rewriteConfiguration = rewriteConfiguration
    }

    func edit(root: Any, provider: String, newAssetID: String) throws -> EditResult {
        let (node, updatedCount, _) = try editNode(root, path: [], provider: provider, newAssetID: newAssetID)
        return EditResult(root: node, updatedCount: updatedCount)
    }

    func scanForProviderNodes(root: Any, provider: String) -> ProviderNodeStats {
        scanForProviderNodes(root, provider: provider, path: [])
    }

    // MARK: - Editing

    /// Returns: (editedNode, updatedProviderCount, didUpdateProviderInSubtree)
    private func editNode(
        _ node: Any,
        path: [String],
        provider: String,
        newAssetID: String
    ) throws -> (Any, Int, Bool) {
        if let dict = node as? [String: Any] {
            return try editDictionaryNode(dict, path: path, provider: provider, newAssetID: newAssetID)
        }
        if let array = node as? [Any] {
            return try editArrayNode(array, path: path, provider: provider, newAssetID: newAssetID)
        }
        return (node, 0, false)
    }

    private func editDictionaryNode(
        _ dictNode: [String: Any],
        path: [String],
        provider: String,
        newAssetID: String
    ) throws -> (Any, Int, Bool) {
        var dict = dictNode
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

        let didUpdateThisNode = try updateProviderIfMatch(&dict, provider: provider, newAssetID: newAssetID)
        updatedCount += didUpdateThisNode ? 1 : 0
        didUpdateInSubtree = didUpdateInSubtree || didUpdateThisNode

        touchTimestampsIfNeeded(&dict, path: path, didUpdateInSubtree: didUpdateInSubtree)
        return (dict, updatedCount, didUpdateInSubtree)
    }

    private func editArrayNode(
        _ arrayNode: [Any],
        path: [String],
        provider: String,
        newAssetID: String
    ) throws -> (Any, Int, Bool) {
        var editedArray: [Any] = []
        editedArray.reserveCapacity(arrayNode.count)

        var updatedCount = 0
        var didUpdateInSubtree = false

        for value in arrayNode {
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

    private func updateProviderIfMatch(
        _ dict: inout [String: Any],
        provider: String,
        newAssetID: String
    ) throws -> Bool {
        guard let providerValue = dict["Provider"] as? String, providerValue == provider else { return false }
        guard let configData = dict["Configuration"] as? Data else { return false }

        let newConfigData = try rewriteConfiguration(configData, newAssetID)
        dict["Configuration"] = newConfigData
        return true
    }

    private func touchTimestampsIfNeeded(_ dict: inout [String: Any], path: [String], didUpdateInSubtree: Bool) {
        guard didUpdateInSubtree, shouldTouchTimestamps(path: path) else { return }
        if dict["LastSet"] != nil { dict["LastSet"] = now() }
        if dict["LastUse"] != nil { dict["LastUse"] = now() }
    }

    private func shouldTouchTimestamps(path: [String]) -> Bool {
        // Legacy shape uses top-level "Desktop"/"Idle".
        // macOS 15 shape can also use a single "Linked" node (desktop + idle together).
        path.contains("Desktop") || path.contains("Idle") || path.contains("Linked")
    }

    // MARK: - Scanning

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
}

