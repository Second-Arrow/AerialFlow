import Foundation
@testable import AerialFlow

// MARK: - FakeCommandRunner

/// Simple in-memory fake for unit tests.
final class FakeCommandRunner: CommandRunner {
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
final class InMemoryFileSystem: FileSystem {
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
    private var files: [URL: Data] = [:]
    private var directories: Set<URL> = []

    init() {}

    func fileExists(at url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return files[url] != nil || directories.contains(url)
    }

    func readData(from url: URL) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = files[url] else { throw FileSystemError.notFound(url) }
        return data
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        lock.lock(); defer { lock.unlock() }
        files[url] = data
        directories.insert(url.deletingLastPathComponent())
    }

    func createDirectory(at url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        directories.insert(url)
    }

    func listFiles(in directory: URL) throws -> [URL] {
        lock.lock(); defer { lock.unlock() }
        guard directories.contains(directory) else { throw FileSystemError.notADirectory(directory) }
        let childFiles = files.keys.filter { $0.deletingLastPathComponent() == directory }
        let childDirs = directories.filter { $0.deletingLastPathComponent() == directory && $0 != directory }
        return (childFiles + childDirs).sorted { $0.path < $1.path }
    }

    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
        lock.lock(); defer { lock.unlock() }
        if let data = files[url] {
            return [.size: NSNumber(value: data.count)]
        }
        if directories.contains(url) { return [:] }
        throw FileSystemError.notFound(url)
    }

    func moveItem(at src: URL, to dst: URL) throws {
        lock.lock(); defer { lock.unlock() }
        guard let data = files[src] else { throw FileSystemError.notFound(src) }
        files[dst] = data
        files[src] = nil
        directories.insert(dst.deletingLastPathComponent())
    }

    func removeItem(at url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        files[url] = nil
    }

    func fileSize(at url: URL) throws -> Int64 {
        let attrs = try attributesOfItem(at: url)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }
}

