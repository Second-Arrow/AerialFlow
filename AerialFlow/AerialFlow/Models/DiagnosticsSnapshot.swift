import Foundation

/// A snapshot of diagnostic information about the app's runtime state.
struct DiagnosticsSnapshot: Sendable, Equatable {
    let detectedVideoDirectory: URL
    let currentMovPath: URL?
    let lastAssetID: String?
    let lastChange: Date?
    let nextScheduledChangeDate: Date?
    let backupCount: Int
    let recentBackupFileNames: [String]
    let storageUsedBytes: Int64?

    private static let displayDateFormatterLock = NSLock()
    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var lastChangeDescription: String? {
        guard let lastChange else { return nil }
        Self.displayDateFormatterLock.lock()
        defer { Self.displayDateFormatterLock.unlock() }
        return Self.displayDateFormatter.string(from: lastChange)
    }

    var nextScheduledChangeDescription: String? {
        guard let nextScheduledChangeDate else { return nil }
        Self.displayDateFormatterLock.lock()
        defer { Self.displayDateFormatterLock.unlock() }
        return Self.displayDateFormatter.string(from: nextScheduledChangeDate)
    }
}

