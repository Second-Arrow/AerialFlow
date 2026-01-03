import Foundation

/// A snapshot of diagnostic information about the app's runtime state.
struct DiagnosticsSnapshot: Sendable, Equatable {
    let detectedVideoDirectory: URL?
    let currentMovPath: URL?
    let lastAssetID: String?
    let lastChange: Date?
    let nextScheduledChangeDate: Date?
    let backupCount: Int
    let recentBackupFileNames: [String]
    let storageUsedBytes: Int64?

    var lastChangeDescription: String? {
        guard let lastChange else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: lastChange)
    }

    var nextScheduledChangeDescription: String? {
        guard let nextScheduledChangeDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: nextScheduledChangeDate)
    }
}

