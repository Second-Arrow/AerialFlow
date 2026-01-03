import Foundation
import os

/// Orchestrates the core pipeline: pick → download → apply → reload.
struct AerialEngine: Sendable {
    struct Report: Sendable, Equatable {
        let chosenAssetID: String
        let didDownload: Bool
        let updatedProviderNodes: Int
    }

    private let logger = Logger(subsystem: "com.secondarrow.AerialFlow", category: "AerialEngine")

    private let catalog: AerialCataloging
    private let picker: AssetPicking
    private let urlSelector: AssetURLSelecting
    private let downloader: AssetDownloadEnsuring
    private let storeEditor: WallpaperApplying
    private let reloader: WallpaperReloading
    private let stateStore: any AerialEngineStateStore
    private let now: @Sendable () -> Date

    init(
        catalog: AerialCataloging,
        picker: AssetPicking,
        urlSelector: AssetURLSelecting,
        downloader: AssetDownloadEnsuring,
        storeEditor: WallpaperApplying,
        reloader: WallpaperReloading,
        stateStore: any AerialEngineStateStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.catalog = catalog
        self.picker = picker
        self.urlSelector = urlSelector
        self.downloader = downloader
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

        var rng = SystemRandomNumberGenerator()
        let chosen = try picker.pickNext(
            assets: snapshot.assets,
            excludedCategoryIDs: settings.excludedCategoryIDs,
            currentAssetID: current,
            randomMode: settings.randomMode,
            rng: &rng
        )

        let url = try urlSelector.pickURL(for: chosen, preference: settings.qualityPreference)
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
}


