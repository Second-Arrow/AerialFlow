import Foundation
import os

/// Default downloader based on URLSession.
final class URLSessionDownloader: Downloading {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func download(from url: URL, timeout: TimeInterval) async throws -> URL {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        let (location, _) = try await session.download(for: request)
        return location
    }
}

/// Ensures an Aerial asset video exists on disk by downloading it if needed.
struct AssetDownloader: Sendable {
    enum DownloadError: LocalizedError {
        case missingURL
        case systemCacheAssetNotFound(assetID: String, expectedDirectory: URL)
        case couldNotCreateDirectory(URL)
        case downloadReturnedMissingTempFile(URL)
        case fileMoveFailed(from: URL, to: URL, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .missingURL:
                return "No download URL provided for the selected asset."
            case .systemCacheAssetNotFound(let assetID, let expectedDirectory):
                return """
                macOS did not provide the Aerial video yet (assetID=\(assetID)) in:
                \(expectedDirectory.path)

                On macOS 15, Aerial videos are managed by macOS and stored in a system cache that AerialFlow cannot write to.
                Open System Settings > Wallpaper, select Aerials, and wait for the video to download, then try again.
                """
            case .couldNotCreateDirectory(let url):
                return "Could not create destination directory: \(url.path)"
            case .downloadReturnedMissingTempFile(let url):
                return "Download did not produce a temporary file for \(url.absoluteString). Please try again."
            case .fileMoveFailed(let from, let to, let underlying):
                return "Failed to move downloaded file from \(from.path) to \(to.path): \(underlying.localizedDescription)"
            }
        }
    }

    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "AssetDownloader")

    private let fileSystem: FileSystem
    private let downloader: Downloading
    private let directoryDetector: ActiveVideoDirectoryDetector
    private let features: AerialFlowFeatures

    /// Minimum file size (bytes) to consider an asset "present".
    private let minimumSizeBytes: Int64

    init(
        fileSystem: FileSystem,
        downloader: Downloading,
        directoryDetector: ActiveVideoDirectoryDetector,
        features: AerialFlowFeatures,
        minimumSizeBytes: Int64 = Constants.minimumAssetFileSizeBytes
    ) {
        self.fileSystem = fileSystem
        self.downloader = downloader
        self.directoryDetector = directoryDetector
        self.features = features
        self.minimumSizeBytes = minimumSizeBytes
    }

    struct Result: Sendable, Equatable {
        let destinationURL: URL
        let didDownload: Bool
    }

    func ensureDownloaded(
        assetID: String,
        url: URL?,
        timeout: TimeInterval
    ) async throws -> Result {
        guard let url else { throw DownloadError.missingURL }

        let detection = try directoryDetector.detect()
        let dir = detection.videoDirectory
        let destination = dir.appendingPathComponent("\(assetID).mov")

        switch features.movDownloadMode {
        case .relyOnSystemCache_macos15:
            // On macOS 15, the active Aerial directory may be a root-owned `idleassetsd` cache.
            // AerialFlow must not attempt to download/write `.mov` files there.
            if fileSystem.fileExists(at: destination) {
                let size = try fileSystem.fileSize(at: destination)
                if size >= minimumSizeBytes {
                    logger.debug("Asset present in system cache: \(destination.path, privacy: .public) size=\(size)")
                    return Result(destinationURL: destination, didDownload: false)
                }
            }

            // IMPORTANT: Do not block the UI waiting for macOS to fetch/cache the video.
            // In this mode, applying the asset ID and reloading wallpaper pipelines is the trigger;
            // the `.mov` may appear later (or require the user to open Wallpaper settings once).
            if timeout <= 0 {
                throw DownloadError.systemCacheAssetNotFound(assetID: assetID, expectedDirectory: dir)
            }

            logger.debug("Asset not yet present in system cache (non-blocking): \(destination.path, privacy: .public)")
            return Result(destinationURL: destination, didDownload: false)

        case .directToVideoDirectory:
            break
        }

        if !fileSystem.fileExists(at: dir) {
            do {
                try fileSystem.createDirectory(at: dir)
            } catch {
                throw DownloadError.couldNotCreateDirectory(dir)
            }
        }

        if fileSystem.fileExists(at: destination) {
            let size = try fileSystem.fileSize(at: destination)
            if size >= minimumSizeBytes {
                logger.debug("Asset already present: \(destination.path, privacy: .public) size=\(size)")
                return Result(destinationURL: destination, didDownload: false)
            }
        }

        let part = dir.appendingPathComponent(".\(assetID).mov.part")
        try? fileSystem.removeItem(at: part)

        let tempLocation = try await downloader.download(from: url, timeout: timeout)
        guard fileSystem.fileExists(at: tempLocation) else {
            throw DownloadError.downloadReturnedMissingTempFile(url)
        }

        do {
            // Copy the temp file into our controlled location, then atomic move.
            // (We avoid moving directly from URLSession temp if cross-device.)
            let data = try fileSystem.readData(from: tempLocation)
            try fileSystem.writeData(data, to: part, options: [.atomic])
            try fileSystem.moveItem(at: part, to: destination)
        } catch {
            throw DownloadError.fileMoveFailed(from: part, to: destination, underlying: error)
        }

        logger.debug("Downloaded asset: \(destination.path, privacy: .public)")
        return Result(destinationURL: destination, didDownload: true)
    }
}

// MARK: - Protocol Conformance

extension AssetDownloader: AssetDownloadEnsuring {}


