import Foundation
import CoreGraphics
import ImageIO
import os

/// Estimates the average brightness (0.0–1.0) of an image.
///
/// This is intentionally pure-ish: given image bytes, it returns a deterministic score.
struct ImageLuminanceEstimator {
    /// Returns a brightness score in the range 0.0–1.0, or nil if decoding fails.
    ///
    /// - Parameters:
    ///   - imageData: Encoded image bytes (PNG/JPEG/etc).
    ///   - targetSize: Downsample size used for computing an average.
    static func brightness(from imageData: Data, targetSize: Int = 32) -> Double? {
        guard targetSize > 0 else { return nil }

        let cfData = imageData as CFData
        guard let source = CGImageSourceCreateWithData(cfData, nil) else { return nil }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let width = targetSize
        let height = targetSize
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.byteOrder32Big)

        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        ctx.interpolationQuality = CGInterpolationQuality.medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sum: Double = 0
        let pixelCount = width * height
        for i in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let r = Double(pixels[i + 0]) / 255.0
            let g = Double(pixels[i + 1]) / 255.0
            let b = Double(pixels[i + 2]) / 255.0
            // Relative luminance (sRGB), clamped to [0,1].
            let y = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
            sum += min(max(y, 0), 1)
        }

        guard pixelCount > 0 else { return nil }
        return sum / Double(pixelCount)
    }
}

/// UserDefaults-backed store for preview-image brightness scores.
actor AerialBrightnessStore: AerialBrightnessStoring {
    enum BrightnessError: LocalizedError {
        case missingPreviewImageURL(assetID: String)
        case couldNotDecodeImage(assetID: String)

        var errorDescription: String? {
            switch self {
            case .missingPreviewImageURL(let assetID):
                return "No preview image URL available for asset \(assetID)."
            case .couldNotDecodeImage(let assetID):
                return "Could not decode preview image for asset \(assetID)."
            }
        }
    }

    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "AerialBrightnessStore")

    private let userDefaults: UserDefaults
    private let fileSystem: any FileSystem
    private let downloader: any Downloading

    private enum Keys {
        static let prefix = "AerialFlow.brightness.v1."
        static func brightnessKey(assetID: String) -> String { "\(prefix)\(assetID)" }
    }

    init(
        userDefaults: UserDefaults = .standard,
        fileSystem: any FileSystem,
        downloader: any Downloading
    ) {
        self.userDefaults = userDefaults
        self.fileSystem = fileSystem
        self.downloader = downloader
    }

    func brightness(for asset: AerialAsset, timeout: TimeInterval) async throws -> Double {
        guard !asset.id.isEmpty else { return 0.0 }
        if let cached = cachedBrightness(assetID: asset.id) {
            return cached
        }

        guard let url = asset.previewImageURL else {
            throw BrightnessError.missingPreviewImageURL(assetID: asset.id)
        }

        let tempURL = try await downloader.download(from: url, timeout: timeout)
        defer { try? fileSystem.removeItem(at: tempURL) }

        let data = try fileSystem.readData(from: tempURL)
        guard let score = ImageLuminanceEstimator.brightness(from: data) else {
            throw BrightnessError.couldNotDecodeImage(assetID: asset.id)
        }

        setCachedBrightness(score, assetID: asset.id)
        return score
    }

    func isDark(assetID: String, threshold: Double) async -> Bool? {
        guard let score = cachedBrightness(assetID: assetID) else { return nil }
        return score < threshold
    }

    func precompute(assets: [AerialAsset], timeout: TimeInterval, maxConcurrency: Int) async {
        guard maxConcurrency > 0 else { return }

        let logger = self.logger
        var iterator = assets.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0

            func enqueueNextIfPossible() {
                guard !Task.isCancelled else { return }
                guard inFlight < maxConcurrency else { return }
                guard let next = iterator.next() else { return }
                guard next.previewImageURL != nil else { return enqueueNextIfPossible() }
                if cachedBrightness(assetID: next.id) != nil { return enqueueNextIfPossible() }

                inFlight += 1
                group.addTask { [timeout] in
                    guard !Task.isCancelled else { return }
                    do {
                        _ = try await self.brightness(for: next, timeout: timeout)
                    } catch {
                        // Precompute is best-effort; keep going.
                        logger.debug("Brightness precompute failed for \(next.id, privacy: .public): \(String(describing: error), privacy: .public)")
                    }
                }
            }

            for _ in 0..<maxConcurrency { enqueueNextIfPossible() }

            while inFlight > 0 {
                await group.next()
                inFlight -= 1
                enqueueNextIfPossible()
            }
        }
    }

    private func cachedBrightness(assetID: String) -> Double? {
        userDefaults.object(forKey: Keys.brightnessKey(assetID: assetID)) as? Double
    }

    private func setCachedBrightness(_ value: Double, assetID: String) {
        userDefaults.set(value, forKey: Keys.brightnessKey(assetID: assetID))
    }
}


