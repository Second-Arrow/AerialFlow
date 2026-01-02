import Foundation
import os

protocol Downloading: Sendable {
    func download(from url: URL, timeout: TimeInterval) async throws -> URL
}

/// Default downloader based on URLSession.
final class URLSessionDownloader: Downloading {
    private let session: URLSession

    init(session: URLSession = .shared) {
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
        case couldNotCreateDirectory(URL)
        case downloadReturnedMissingTempFile(URL)
        case fileMoveFailed(from: URL, to: URL, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .missingURL:
                return "No download URL provided for the selected asset."
            case .couldNotCreateDirectory(let url):
                return "Could not create destination directory: \(url.path)"
            case .downloadReturnedMissingTempFile(let url):
                return "Download did not produce a temporary file for \(url.absoluteString)."
            case .fileMoveFailed(let from, let to, let underlying):
                return "Failed to move downloaded file from \(from.path) to \(to.path): \(underlying.localizedDescription)"
            }
        }
    }

    private let logger = Logger(subsystem: "com.secondarrow.AerialFlow", category: "AssetDownloader")

    private let fileSystem: FileSystem
    private let downloader: Downloading
    private let directoryDetector: ActiveVideoDirectoryDetector

    /// Minimum file size (bytes) to consider an asset “present”.
    private let minimumSizeBytes: Int64

    init(
        fileSystem: FileSystem = DefaultFileSystem(),
        downloader: Downloading = URLSessionDownloader(),
        directoryDetector: ActiveVideoDirectoryDetector,
        minimumSizeBytes: Int64 = 5 * 1024 * 1024
    ) {
        self.fileSystem = fileSystem
        self.downloader = downloader
        self.directoryDetector = directoryDetector
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

        if !fileSystem.fileExists(at: dir) {
            do {
                try fileSystem.createDirectory(at: dir)
            } catch {
                throw DownloadError.couldNotCreateDirectory(dir)
            }
        }

        let destination = dir.appendingPathComponent("\(assetID).mov")

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


