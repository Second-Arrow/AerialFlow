import Foundation
import os

/// Backup naming and retention management for the wallpaper store `Index.plist`.
///
/// Backups are stored next to the original file using a timestamped name:
/// `Index.plist.yyyyMMdd-HHmmss.bak`
struct WallpaperStoreBackupRetention: Sendable {
    private let fileSystem: FileSystem
    private let logger: Logger

    init(fileSystem: FileSystem, logger: Logger) {
        self.fileSystem = fileSystem
        self.logger = logger
    }

    func backupURL(for indexPlistURL: URL, date: Date) -> URL {
        let stamp = timestampString(for: date)
        let dir = indexPlistURL.deletingLastPathComponent()
        let name = "\(indexPlistURL.lastPathComponent).\(stamp).bak"
        return dir.appendingPathComponent(name)
    }

    func pruneBackupsBestEffort(indexPlistURL: URL, keepingMostRecent count: Int) {
        let keepCount = max(1, count)
        let dir = indexPlistURL.deletingLastPathComponent()
        let prefix = "\(indexPlistURL.lastPathComponent)."

        let files: [URL]
        do {
            files = try fileSystem.listFiles(in: dir)
        } catch {
            logger.debug("Backup retention: could not list backups in \(dir.path, privacy: .public)")
            return
        }

        let backups = files
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix(prefix) && name.hasSuffix(".bak")
            }
            // Name sorts by timestamp (yyyyMMdd-HHmmss), so descending keeps newest first.
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard backups.count > keepCount else { return }

        for url in backups.dropFirst(keepCount) {
            do {
                try fileSystem.removeItem(at: url)
            } catch {
                logger.debug("Backup retention: failed to remove \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func timestampString(for date: Date) -> String {
        // Constructing a DateFormatter is cheap enough at this call frequency and avoids shared mutable state.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

