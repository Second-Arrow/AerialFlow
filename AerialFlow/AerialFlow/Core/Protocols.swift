import Foundation

// MARK: - AerialEngine Dependencies

/// Protocol for loading the Aerial catalog.
protocol AerialCataloging: Sendable {
    func loadSnapshot() async throws -> AerialCatalog.Snapshot
}

/// Protocol for picking the next eligible asset.
protocol AssetPicking: Sendable {
    func pickNext(
        assets: [AerialAsset],
        excludedCategoryIDs: Set<String>,
        excludedSubcategoryIDs: Set<String>,
        currentAssetID: String?,
        randomMode: Bool,
        rng: inout some RandomNumberGenerator
    ) throws -> AerialAsset
}

/// Protocol for selecting a download URL for an asset.
protocol AssetURLSelecting: Sendable {
    func pickURL(for asset: AerialAsset) throws -> URL
}

/// Protocol for ensuring an asset is downloaded.
protocol AssetDownloadEnsuring: Sendable {
    func ensureDownloaded(assetID: String, url: URL?, timeout: TimeInterval) async throws -> AssetDownloader.Result
}

/// Protocol for applying an asset ID to the wallpaper store.
protocol WallpaperApplying: Sendable {
    func applyAerialAssetID(_ assetID: String, indexPlistURL: URL, backupRetentionCount: Int) throws -> WallpaperStoreEditor.ApplyResult
}

/// Protocol for reloading wallpaper pipelines.
protocol WallpaperReloading: Sendable {
    func reloadWallpaperPipelines()
}

/// Protocol for downloading files from URLs.
protocol Downloading: Sendable {
    func download(from url: URL, timeout: TimeInterval) async throws -> URL
}

/// Guardrail checks to decide whether wallpaper rotation should proceed.
protocol RunGuarding: Sendable {
    nonisolated func shouldRunNow(settings: any RunGuardSettings) -> Bool
}

// MARK: - AerialEngine Configuration

/// Settings required by AerialEngine.
protocol AerialEngineSettings: Sendable {
    var excludedCategoryIDs: Set<String> { get }
    var excludedSubcategoryIDs: Set<String> { get }
    var randomMode: Bool { get }
    var downloadTimeout: TimeInterval { get }
    var indexPlistURL: URL { get }
    var backupRetentionCount: Int { get }
}

/// Settings required by `RunGuard` to determine whether it should block rotation.
protocol RunGuardSettings: Sendable {
    var skipWhenDisplayOff: Bool { get }
    var skipWhenScreensaverActive: Bool { get }
    var skipAtLoginWindow: Bool { get }
}

/// State store for AerialEngine runtime state.
protocol AerialEngineStateStore: Sendable {
    func getLastAssetID() async -> String?
    func setLastAssetID(_ id: String?) async
    func getLastChange() async -> Date?
    func setLastChange(_ date: Date?) async
}

// MARK: - Launch at Login

enum LaunchAtLoginStatus: Sendable, Equatable {
    case enabled
    case disabled
    case requiresApproval
}

protocol LaunchAtLoginManaging: Sendable {
    func status() -> LaunchAtLoginStatus
    func register() throws
    func unregister() throws
}

