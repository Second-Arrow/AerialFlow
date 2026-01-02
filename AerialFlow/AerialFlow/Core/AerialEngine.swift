import Foundation
import os

/// Orchestrates the core pipeline: pick → download → apply → reload.
struct AerialEngine: Sendable {
    enum EngineError: LocalizedError {
        case noEligibleAssets

        var errorDescription: String? {
            switch self {
            case .noEligibleAssets:
                return "No eligible assets were available to pick."
            }
        }
    }

    struct Report: Sendable, Equatable {
        let chosenAssetID: String
        let didDownload: Bool
        let updatedProviderNodes: Int
    }

    private let logger = Logger(subsystem: "com.secondarrow.AerialFlow", category: "AerialEngine")

    private let catalog: AerialCataloging
    private let categoryResolver: CategoryResolver
    private let picker: AssetPicking
    private let urlSelector: AssetURLSelecting
    private let downloader: AssetDownloadEnsuring
    private let storeEditor: WallpaperApplying
    private let reloader: WallpaperReloading
    private let settings: any AerialEngineSettings
    private let stateStore: any AerialEngineStateStore
    private let now: @Sendable () -> Date

    init(
        catalog: AerialCataloging,
        categoryResolver: CategoryResolver,
        picker: AssetPicking,
        urlSelector: AssetURLSelecting,
        downloader: AssetDownloadEnsuring,
        storeEditor: WallpaperApplying,
        reloader: WallpaperReloading,
        settings: any AerialEngineSettings,
        stateStore: any AerialEngineStateStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.catalog = catalog
        self.categoryResolver = categoryResolver
        self.picker = picker
        self.urlSelector = urlSelector
        self.downloader = downloader
        self.storeEditor = storeEditor
        self.reloader = reloader
        self.settings = settings
        self.stateStore = stateStore
        self.now = now
    }

    /// Advances to the next Aerial. Manual/scheduled semantics can be layered on later; Milestone 1 always updates last-change.
    @discardableResult
    func next(manual: Bool) async throws -> Report {
        _ = manual

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

        // Keep resolver in the dependency graph (used by UI later); touch it here for a cheap sanity check.
        _ = categoryResolver.categoryIDToNames(categories: snapshot.categories)

        let url = try urlSelector.pickURL(for: chosen, preference: settings.qualityPreference)
        let downloadResult = try await downloader.ensureDownloaded(assetID: chosen.id, url: url, timeout: settings.downloadTimeout)

        let applyResult = try storeEditor.applyAerialAssetID(chosen.id, indexPlistURL: settings.indexPlistURL)
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


