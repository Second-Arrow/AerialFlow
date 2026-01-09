import Foundation

// MARK: - AerialEngine Dependencies

enum PowerEvent: Sendable, Equatable {
    case willSleep
    case didWake
    case screensDidSleep
    case screensDidWake
}

/// Emits system sleep/wake and screen sleep/wake events.
///
/// This is a system-boundary seam so `Core/` logic can be tested without AppKit.
protocol PowerEventObserving: Sendable {
    func events() -> AsyncStream<PowerEvent>
}

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
        excludedAssetIDs: Set<String>,
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

    func inspectAerialConfiguration(indexPlistURL: URL) throws -> WallpaperStoreEditor.AerialConfigurationStatus

    func repairAerialConfiguration(
        desiredAssetID: String,
        indexPlistURL: URL,
        backupRetentionCount: Int
    ) throws -> WallpaperStoreEditor.AerialConfigurationRepairReport
}

/// Protocol for reloading wallpaper pipelines.
protocol WallpaperReloading: Sendable {
    func reloadWallpaperPipelines()
}

/// Protocol for downloading files from URLs.
protocol Downloading: Sendable {
    func download(from url: URL, timeout: TimeInterval) async throws -> URL
}

// MARK: - Brightness Scoring

/// Provides a cached brightness score (0.0–1.0) for Aerial preview images.
protocol AerialBrightnessStoring: Sendable {
    /// Returns a brightness score in the range 0.0–1.0 for the given asset.
    /// Implementations may cache results and reuse them across launches.
    func brightness(for asset: AerialAsset, timeout: TimeInterval) async throws -> Double

    /// Returns whether the asset is considered dark based on a threshold, or nil if unknown.
    func isDark(assetID: String, threshold: Double) async -> Bool?

    /// Precomputes brightness scores for a set of assets.
    /// This should be cancellation-aware and bound concurrency to `maxConcurrency`.
    func precompute(assets: [AerialAsset], timeout: TimeInterval, maxConcurrency: Int) async
}

// MARK: - AerialEngine Configuration

/// Settings required by AerialEngine.
protocol AerialEngineSettings: Sendable {
    var excludedCategoryIDs: Set<String> { get }
    var excludedSubcategoryIDs: Set<String> { get }
    var excludedAssetIDs: Set<String> { get }
    var randomMode: Bool { get }
    var downloadTimeout: TimeInterval { get }
    var indexPlistURL: URL { get }
    var backupRetentionCount: Int { get }
    var isLightSensitiveFilteringEnabled: Bool { get }
    var allowedLightStartMinutes: Int { get }
    var allowedLightEndMinutes: Int { get }
    var lightSensitivity: Double { get }
}

/// State store for AerialEngine runtime state.
protocol AerialEngineStateStore: Sendable {
    func getLastAssetID() async -> String?
    func setLastAssetID(_ id: String?) async
    func getLastChange() async -> Date?
    func setLastChange(_ date: Date?) async
}

// MARK: - Excluded Aerial Cleanup

/// State store for the daily excluded-aerial cleanup scheduler.
protocol ExcludedAerialsCleanupStateStoring: Sendable {
    /// When the user last enabled auto-cleanup (used to delay the first run ~24h after enabling).
    func getAutoCleanupEnabledSince() async -> Date?
    func setAutoCleanupEnabledSince(_ date: Date?) async

    /// Last successful auto-cleanup run time (manual "Clean Now" does not update this).
    func getLastAutoCleanupRunDate() async -> Date?
    func setLastAutoCleanupRunDate(_ date: Date?) async
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

