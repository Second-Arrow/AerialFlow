import Foundation
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

// MARK: - RunGuard Fakes

/// A run guard that always allows rotation.
struct AlwaysRunGuard: RunGuarding {
    func shouldRunNow(settings: any RunGuardSettings) -> Bool {
        true
    }
}

/// A run guard that never allows rotation.
struct NeverRunGuard: RunGuarding {
    func shouldRunNow(settings: any RunGuardSettings) -> Bool {
        false
    }
}

// MARK: - Counter

/// Thread-safe counter actor for test assertions.
actor Counter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
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

    init() {}

    func fileExists(at url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return files[url.path] != nil || directories.contains(url.path)
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

