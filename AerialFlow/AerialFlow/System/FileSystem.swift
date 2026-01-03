import Foundation

/// A small seam around file IO, to keep `Core/` testable.
protocol FileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func readData(from url: URL) throws -> Data
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws
    func createDirectory(at url: URL) throws
    func listFiles(in directory: URL) throws -> [URL]
    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any]
    func moveItem(at src: URL, to dst: URL) throws
    func removeItem(at url: URL) throws
    func fileSize(at url: URL) throws -> Int64
}

struct DefaultFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func readData(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        try data.write(to: url, options: options)
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func listFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    }

    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: url.path)
    }

    func moveItem(at src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.moveItem(at: src, to: dst)
    }

    func removeItem(at url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    func fileSize(at url: URL) throws -> Int64 {
        let attrs = try attributesOfItem(at: url)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }
}

