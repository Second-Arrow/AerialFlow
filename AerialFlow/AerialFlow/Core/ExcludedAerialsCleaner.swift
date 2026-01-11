import Foundation
import os

struct ExcludedAerialsCleanupReport: Sendable, Equatable {
    struct Failure: Sendable, Equatable {
        let fileURL: URL
        let errorDescription: String
    }

    let removedFiles: [URL]
    let failures: [Failure]

    var removedCount: Int { removedFiles.count }
}

/// Removes excluded Aerial `.mov` files from the storage location.
///
/// Exclusions are defined by the app settings (categories, subcategories, and explicit asset IDs).
struct ExcludedAerialsCleaner: Sendable {
    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "ExcludedAerialsCleaner")

    private let fileSystem: any FileSystem
    private let directoryDetector: ActiveVideoDirectoryDetector
    private let catalog: any AerialCataloging
    private let features: AerialFlowFeatures

    init(
        fileSystem: any FileSystem,
        directoryDetector: ActiveVideoDirectoryDetector,
        catalog: any AerialCataloging,
        features: AerialFlowFeatures
    ) {
        self.fileSystem = fileSystem
        self.directoryDetector = directoryDetector
        self.catalog = catalog
        self.features = features
    }

    func cleanExcludedMovFiles(settings: AppSettings) async throws -> ExcludedAerialsCleanupReport {
        if features.movDownloadMode == .relyOnSystemCache_macos15 {
            // On macOS 15 the active Aerial video directory is system-managed (idleassetsd cache).
            // Do not attempt to remove system cache files.
            logger.info("Excluded Aerial cleanup skipped: system-managed cache on macOS 15.")
            return ExcludedAerialsCleanupReport(removedFiles: [], failures: [])
        }

        let snapshot = try await catalog.loadSnapshot()
        let excludedMain = settings.excludedCategoryIDs
        let excludedSub = settings.excludedSubcategoryIDs
        let excludedAssets = settings.excludedAssetIDs

        let excludedAssetIDs = snapshot.assets
            .filter { asset in
                guard !asset.id.isEmpty else { return false }
                if excludedMain.isEmpty, excludedSub.isEmpty, excludedAssets.isEmpty { return false }
                return asset.isExcluded(
                    excludedMainCategoryIDs: excludedMain,
                    excludedSubcategoryIDs: excludedSub,
                    excludedAssetIDs: excludedAssets
                )
            }
            .map(\.id)

        guard !excludedAssetIDs.isEmpty else {
            return ExcludedAerialsCleanupReport(removedFiles: [], failures: [])
        }

        let detection = try directoryDetector.detect()
        let videoDirectory = detection.videoDirectory

        var removed: [URL] = []
        removed.reserveCapacity(min(excludedAssetIDs.count, 32))
        var failures: [ExcludedAerialsCleanupReport.Failure] = []

        for assetID in excludedAssetIDs {
            let fileURL = videoDirectory.appendingPathComponent("\(assetID).mov")
            guard fileSystem.fileExists(at: fileURL) else { continue }
            do {
                try fileSystem.removeItem(at: fileURL)
                removed.append(fileURL)
            } catch {
                failures.append(.init(fileURL: fileURL, errorDescription: error.localizedDescription))
            }
        }

        if failures.isEmpty {
            if removed.isEmpty {
                logger.info("Excluded Aerial cleanup: nothing to remove.")
            } else {
                logger.info("Excluded Aerial cleanup: removed \(removed.count, privacy: .public) file(s).")
            }
        } else {
            logger.error("Excluded Aerial cleanup: removed \(removed.count, privacy: .public) file(s), failed \(failures.count, privacy: .public).")
        }

        return ExcludedAerialsCleanupReport(removedFiles: removed, failures: failures)
    }
}


