import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import UserNotifications
@testable import AerialFlow

// MARK: - FakeEngineStateStore

/// In-memory fake for AerialEngineStateStore, useful for unit tests.
actor FakeEngineStateStore: AerialEngineStateStore {
    private var lastAssetID: String?
    private var lastChange: Date?

    init(lastAssetID: String? = nil, lastChange: Date? = nil) {
        self.lastAssetID = lastAssetID
        self.lastChange = lastChange
    }

    func getLastAssetID() async -> String? { lastAssetID }
    func setLastAssetID(_ id: String?) async { lastAssetID = id }
    func getLastChange() async -> Date? { lastChange }
    func setLastChange(_ date: Date?) async { lastChange = date }
}

// MARK: - FakeExcludedAerialsCleanupStateStore

actor FakeExcludedAerialsCleanupStateStore: ExcludedAerialsCleanupStateStoring {
    private var autoCleanupEnabledSince: Date?
    private var lastAutoCleanupRunDate: Date?

    init(autoCleanupEnabledSince: Date? = nil, lastAutoCleanupRunDate: Date? = nil) {
        self.autoCleanupEnabledSince = autoCleanupEnabledSince
        self.lastAutoCleanupRunDate = lastAutoCleanupRunDate
    }

    func getAutoCleanupEnabledSince() async -> Date? { autoCleanupEnabledSince }
    func setAutoCleanupEnabledSince(_ date: Date?) async { autoCleanupEnabledSince = date }

    func getLastAutoCleanupRunDate() async -> Date? { lastAutoCleanupRunDate }
    func setLastAutoCleanupRunDate(_ date: Date?) async { lastAutoCleanupRunDate = date }
}

// MARK: - PowerEventObserving Fakes

struct EmptyPowerEventObserver: PowerEventObserving, Sendable {
    func events() -> AsyncStream<PowerEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

struct SequencePowerEventObserver: PowerEventObserving, Sendable {
    let eventsToEmit: [PowerEvent]

    func events() -> AsyncStream<PowerEvent> {
        AsyncStream { continuation in
            for event in eventsToEmit {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

// MARK: - SeededRNG

/// A deterministic random number generator for repeatable tests.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        // SplitMix64 algorithm
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Counter

/// Thread-safe counter actor for test assertions.
actor Counter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

// MARK: - Test Image Helpers

enum TestImageFactory {
    static func pngData(rgba: (UInt8, UInt8, UInt8, UInt8)) throws -> Data {
        var pixel = [rgba.0, rgba.1, rgba.2, rgba.3]
        let width = 1
        let height = 1
        let bytesPerRow = 4

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.byteOrder32Big)

        guard let ctx = CGContext(
            data: &pixel,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw NSError(domain: "TestImageFactory", code: 1)
        }

        guard let image = ctx.makeImage() else {
            throw NSError(domain: "TestImageFactory", code: 2)
        }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "TestImageFactory", code: 3)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "TestImageFactory", code: 4)
        }

        return out as Data
    }
}

// MARK: - Brightness Store Fakes

actor NoopBrightnessStore: AerialBrightnessStoring {
    func brightness(for asset: AerialAsset, timeout: TimeInterval) async throws -> Double {
        _ = asset
        _ = timeout
        return 0.5
    }

    func isDark(assetID: String, threshold: Double) async -> Bool? {
        _ = assetID
        _ = threshold
        return nil
    }

    func precompute(assets: [AerialAsset], timeout: TimeInterval, maxConcurrency: Int) async {
        _ = assets
        _ = timeout
        _ = maxConcurrency
    }
}

actor FixedDarknessBrightnessStore: AerialBrightnessStoring {
    private let darkAssetIDs: Set<String>
    private let unknownAssetIDs: Set<String>

    init(darkAssetIDs: Set<String>, unknownAssetIDs: Set<String> = []) {
        self.darkAssetIDs = darkAssetIDs
        self.unknownAssetIDs = unknownAssetIDs
    }

    func brightness(for asset: AerialAsset, timeout: TimeInterval) async throws -> Double {
        _ = asset
        _ = timeout
        return 0.5
    }

    func isDark(assetID: String, threshold: Double) async -> Bool? {
        _ = threshold
        if unknownAssetIDs.contains(assetID) { return nil }
        return darkAssetIDs.contains(assetID)
    }

    func precompute(assets: [AerialAsset], timeout: TimeInterval, maxConcurrency: Int) async {
        _ = assets
        _ = timeout
        _ = maxConcurrency
    }
}

// MARK: - FakeCommandRunner

/// Simple in-memory fake for unit tests.
///
/// `CommandRunner` is `Sendable`, but this test fake has internal mutable state guarded by `NSLock`,
/// so we use `@unchecked Sendable` to silence strict Swift 6 Sendable checking.
final class FakeCommandRunner: CommandRunner, @unchecked Sendable {
    struct Invocation: Equatable, Sendable {
        let command: Command
    }

    private let lock = NSLock()
    private(set) var invocations: [Invocation] = []
    private var stubs: [Command: CommandResult] = [:]

    init() {}

    func stub(_ command: Command, result: CommandResult) {
        lock.lock()
        defer { lock.unlock() }
        stubs[command] = result
    }

    func run(_ command: Command) throws -> CommandResult {
        lock.lock()
        invocations.append(Invocation(command: command))
        let result = stubs[command] ?? CommandResult(exitCode: 127, stdout: "", stderr: "Command not stubbed")
        lock.unlock()
        return result
    }
}

// MARK: - Permission / System Settings Fakes

struct NoopNotificationPermissionService: NotificationPermissionServicing {
    func authorizationStatus() async -> UNAuthorizationStatus { .notDetermined }
    func requestAuthorizationIfNeeded() async -> Bool { false }
    func requestAuthorization() async -> Bool { false }
    func postErrorNotificationIfPossible(_ message: String) async { _ = message }
}

struct NoopSystemSettingsOpener: SystemSettingsOpening {
    func openSystemSettings() -> Bool { false }
    func openNotificationsSettings() -> Bool { false }
    func openLoginItemsSettings() -> Bool { false }
    func openInputMonitoringSettings() -> Bool { false }
    func openAccessibilitySettings() -> Bool { false }
    func openWallpaperSettings() -> Bool { false }
    func openScreenSaverSettings() -> Bool { false }
}

// MARK: - InMemoryFileSystem

/// In-memory fake filesystem for unit tests.
///
/// `FileSystem` is `Sendable`, but this test fake has internal mutable state guarded by `NSLock`,
/// so we use `@unchecked Sendable` to silence strict Swift 6 Sendable checking.
final class InMemoryFileSystem: FileSystem, @unchecked Sendable {
    enum FileSystemError: LocalizedError {
        case notFound(URL)
        case notADirectory(URL)

        var errorDescription: String? {
            switch self {
            case .notFound(let url): return "File not found: \(url.path)"
            case .notADirectory(let url): return "Not a directory: \(url.path)"
            }
        }
    }

    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var directories: Set<String> = []
    private var unreadablePaths: Set<String> = []
    private var unwritablePaths: Set<String> = []

    init() {}

    func fileExists(at url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return files[url.path] != nil || directories.contains(url.path)
    }

    func isReadable(at url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard files[url.path] != nil || directories.contains(url.path) else { return false }
        return !unreadablePaths.contains(url.path)
    }

    func isWritable(at url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        // Allow writability checks for paths that may not exist yet (e.g. "can I create this directory?").
        return !unwritablePaths.contains(url.path)
    }

    func setReadable(_ readable: Bool, for url: URL) {
        lock.lock(); defer { lock.unlock() }
        if readable {
            unreadablePaths.remove(url.path)
        } else {
            unreadablePaths.insert(url.path)
        }
    }

    func setWritable(_ writable: Bool, for url: URL) {
        lock.lock(); defer { lock.unlock() }
        if writable {
            unwritablePaths.remove(url.path)
        } else {
            unwritablePaths.insert(url.path)
        }
    }

    func readData(from url: URL) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = files[url.path] else { throw FileSystemError.notFound(url) }
        return data
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        lock.lock(); defer { lock.unlock() }
        files[url.path] = data
        directories.insert(url.deletingLastPathComponent().path)
    }

    func createDirectory(at url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        directories.insert(url.path)
    }

    func listFiles(in directory: URL) throws -> [URL] {
        lock.lock(); defer { lock.unlock() }
        let dirPath = directory.path
        guard directories.contains(dirPath) else { throw FileSystemError.notADirectory(directory) }

        let childFilePaths = files.keys.filter { URL(fileURLWithPath: $0).deletingLastPathComponent().path == dirPath }
        let childDirPaths = directories.filter {
            URL(fileURLWithPath: $0, isDirectory: true).deletingLastPathComponent().path == dirPath && $0 != dirPath
        }

        let childFileURLs = childFilePaths.map { URL(fileURLWithPath: $0) }
        let childDirURLs = childDirPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }

        return (childFileURLs + childDirURLs).sorted { $0.path < $1.path }
    }

    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
        lock.lock(); defer { lock.unlock() }
        if let data = files[url.path] {
            return [.size: NSNumber(value: data.count)]
        }
        if directories.contains(url.path) { return [:] }
        throw FileSystemError.notFound(url)
    }

    func moveItem(at src: URL, to dst: URL) throws {
        lock.lock(); defer { lock.unlock() }
        guard let data = files[src.path] else { throw FileSystemError.notFound(src) }
        files[dst.path] = data
        files[src.path] = nil
        directories.insert(dst.deletingLastPathComponent().path)
    }

    func removeItem(at url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        files[url.path] = nil
    }

    func fileSize(at url: URL) throws -> Int64 {
        let attrs = try attributesOfItem(at: url)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }
}

