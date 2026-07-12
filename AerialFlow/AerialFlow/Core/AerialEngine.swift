import Foundation
import os

/// Orchestrates the core pipeline: pick → download → apply → reload.
struct AerialEngine: Sendable {
    struct Report: Sendable, Equatable {
        let chosenAssetID: String
        let didDownload: Bool
        let updatedProviderNodes: Int
    }

    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "AerialEngine")

    private let catalog: AerialCataloging
    private let picker: AssetPicking
    private let urlSelector: AssetURLSelecting
    private let downloader: AssetDownloadEnsuring
    private let brightnessStore: any AerialBrightnessStoring
    private let storeEditor: WallpaperApplying
    private let reloader: WallpaperReloading
    private let stateStore: any AerialEngineStateStore
    private let features: AerialFlowFeatures
    private let now: @Sendable () -> Date

    init(
        catalog: AerialCataloging,
        picker: AssetPicking,
        urlSelector: AssetURLSelecting,
        downloader: AssetDownloadEnsuring,
        brightnessStore: any AerialBrightnessStoring,
        storeEditor: WallpaperApplying,
        reloader: WallpaperReloading,
        stateStore: any AerialEngineStateStore,
        features: AerialFlowFeatures = AerialFlowFeatures(movDownloadMode: .directToVideoDirectory),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.catalog = catalog
        self.picker = picker
        self.urlSelector = urlSelector
        self.downloader = downloader
        self.brightnessStore = brightnessStore
        self.storeEditor = storeEditor
        self.reloader = reloader
        self.stateStore = stateStore
        self.features = features
        self.now = now
    }

    /// Executes the core pipeline: filter → pick → download → apply → reload.
    private func executeNextPipeline(
        assets: [AerialAsset],
        randomMode: Bool,
        settings: any AerialEngineSettings,
        logContext: String
    ) async throws -> Report {
        let current = await stateStore.getLastAssetID()

        let filter = LightSensitiveAssetFilter(now: now)
        let filteredAssets = await filter.filterIfNeeded(
            assets: assets,
            settings: settings,
            brightnessStore: brightnessStore
        )

        var rng = SystemRandomNumberGenerator()
        let chosen = try picker.pickNext(
            assets: filteredAssets,
            excludedCategoryIDs: settings.excludedCategoryIDs,
            excludedSubcategoryIDs: settings.excludedSubcategoryIDs,
            excludedAssetIDs: settings.excludedAssetIDs,
            currentAssetID: current,
            randomMode: randomMode,
            rng: &rng
        )

        let url = try urlSelector.pickURL(for: chosen)

        func applyChosenAsset() throws -> WallpaperStoreEditor.ApplyResult {
            do {
                return try storeEditor.applyAerialAssetID(
                    chosen.id,
                    indexPlistURL: settings.indexPlistURL,
                    backupRetentionCount: settings.backupRetentionCount
                )
            } catch let error as WallpaperStoreEditor.EditorError {
                switch error {
                case .noProviderNodesFound:
                    // Best-effort self-healing: attempt to upsert provider nodes (when safe) and retry apply.
                    _ = try storeEditor.repairAerialConfiguration(
                        desiredAssetID: chosen.id,
                        indexPlistURL: settings.indexPlistURL,
                        backupRetentionCount: settings.backupRetentionCount
                    )
                    return try storeEditor.applyAerialAssetID(
                        chosen.id,
                        indexPlistURL: settings.indexPlistURL,
                        backupRetentionCount: settings.backupRetentionCount
                    )
                default:
                    throw error
                }
            }
        }

        let downloadResult: AssetDownloader.Result
        let applyResult: WallpaperStoreEditor.ApplyResult
        switch features.movDownloadMode {
        case .directToVideoDirectory:
            // Default behavior: ensure `.mov` is present before applying.
            downloadResult = try await downloader.ensureDownloaded(assetID: chosen.id, url: url, timeout: settings.downloadTimeout)
            applyResult = try applyChosenAsset()
            reloader.reloadWallpaperPipelines()

        case .relyOnSystemCache_macos15:
            // macOS 15: applying + reloading is what prompts macOS to fetch/cache the `.mov`.
            applyResult = try applyChosenAsset()
            reloader.reloadWallpaperPipelines()
            downloadResult = try await downloader.ensureDownloaded(assetID: chosen.id, url: url, timeout: settings.downloadTimeout)
        }

        await stateStore.setLastAssetID(chosen.id)
        await stateStore.setLastChange(now())

        logger.debug("\(logContext) assetID=\(chosen.id, privacy: .public)")
        return Report(
            chosenAssetID: chosen.id,
            didDownload: downloadResult.didDownload,
            updatedProviderNodes: applyResult.updatedProviderNodeCount
        )
    }

    /// Advances to the next Aerial.
    @discardableResult
    func next(settings: any AerialEngineSettings) async throws -> Report {
        let snapshot = try await catalog.loadSnapshot()
        // Never auto-select non-landscape Aerials (e.g. the portrait "Mac" wallpapers on macOS 26).
        let landscapeAssets = NonLandscapeAerialFilter().filter(
            assets: snapshot.assets,
            categories: snapshot.categories
        )
        return try await executeNextPipeline(
            assets: landscapeAssets,
            randomMode: settings.randomMode,
            settings: settings,
            logContext: "Next applied"
        )
    }

    /// Advances to the next Aerial within a specific subcategory.
    ///
    /// Deterministic by design: `randomMode` is forced off for this operation.
    @discardableResult
    func nextInSubcategory(settings: any AerialEngineSettings, subcategoryID: String) async throws -> Report {
        let snapshot = try await catalog.loadSnapshot()

        let subcategoryAssets = snapshot.assets.filter { asset in
            guard !subcategoryID.isEmpty else { return false }
            return asset.subcategories.contains(subcategoryID)
        }

        return try await executeNextPipeline(
            assets: subcategoryAssets,
            randomMode: false,
            settings: settings,
            logContext: "Next-in-subcategory applied subcategoryID=\(subcategoryID)"
        )
    }
}


