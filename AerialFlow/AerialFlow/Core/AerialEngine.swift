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
        self.now = now
    }

    /// Advances to the next Aerial.
    @discardableResult
    func next(settings: any AerialEngineSettings) async throws -> Report {
        let snapshot = try await catalog.loadSnapshot()
        let current = await stateStore.getLastAssetID()

        let filter = LightSensitiveAssetFilter(now: now)
        let filteredAssets = await filter.filterIfNeeded(
            assets: snapshot.assets,
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
            randomMode: settings.randomMode,
            rng: &rng
        )

        let url = try urlSelector.pickURL(for: chosen)
        let downloadResult = try await downloader.ensureDownloaded(assetID: chosen.id, url: url, timeout: settings.downloadTimeout)

        let applyResult = try storeEditor.applyAerialAssetID(
            chosen.id,
            indexPlistURL: settings.indexPlistURL,
            backupRetentionCount: settings.backupRetentionCount
        )
        reloader.reloadWallpaperPipelines()

        await stateStore.setLastAssetID(chosen.id)
        await stateStore.setLastChange(now())

        logger.debug("Next applied assetID=\(chosen.id, privacy: .public)")
        return Report(
            chosenAssetID: chosen.id,
            didDownload: downloadResult.didDownload,
            updatedProviderNodes: applyResult.updatedProviderNodeCount
        )
    }

    /// Advances to the next Aerial within a specific subcategory.
    ///
    /// Deterministic by design: `randomMode` is forced off for this operation.
    @discardableResult
    func nextInSubcategory(settings: any AerialEngineSettings, subcategoryID: String) async throws -> Report {
        let snapshot = try await catalog.loadSnapshot()
        let current = await stateStore.getLastAssetID()

        let subcategoryAssets = snapshot.assets.filter { asset in
            guard !subcategoryID.isEmpty else { return false }
            return asset.subcategories.contains(subcategoryID)
        }

        let filter = LightSensitiveAssetFilter(now: now)
        let filteredAssets = await filter.filterIfNeeded(
            assets: subcategoryAssets,
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
            randomMode: false,
            rng: &rng
        )

        let url = try urlSelector.pickURL(for: chosen)
        let downloadResult = try await downloader.ensureDownloaded(assetID: chosen.id, url: url, timeout: settings.downloadTimeout)

        let applyResult = try storeEditor.applyAerialAssetID(
            chosen.id,
            indexPlistURL: settings.indexPlistURL,
            backupRetentionCount: settings.backupRetentionCount
        )
        reloader.reloadWallpaperPipelines()

        await stateStore.setLastAssetID(chosen.id)
        await stateStore.setLastChange(now())

        logger.debug("Next-in-subcategory applied assetID=\(chosen.id, privacy: .public) subcategoryID=\(subcategoryID, privacy: .public)")
        return Report(
            chosenAssetID: chosen.id,
            didDownload: downloadResult.didDownload,
            updatedProviderNodes: applyResult.updatedProviderNodeCount
        )
    }
}


