import Foundation

/// Global constants for AerialFlow.
enum Constants {
    /// The subsystem identifier used for all Logger instances.
    static let loggerSubsystem = "com.secondarrow.AerialFlow"

    // MARK: - File Size Thresholds

    /// Minimum file size (bytes) to consider an asset video "present" and not corrupted.
    static let minimumAssetFileSizeBytes: Int64 = 5 * 1024 * 1024

    // MARK: - Timing Defaults

    /// Default rotation interval in seconds (10 minutes).
    static let defaultRotationIntervalSeconds = 600

    /// Minimum allowed rotation interval in seconds (1 minute).
    static let minimumRotationIntervalSeconds = 60

    /// Maximum allowed rotation interval in minutes (4 hours) - used by UI stepper.
    static let maximumRotationIntervalMinutes = 240

    /// Default download timeout in seconds (30 minutes).
    static let defaultDownloadTimeoutSeconds: TimeInterval = 1800

    /// One hour in nanoseconds - used for long sleep intervals.
    static let oneHourNanoseconds: UInt64 = 60 * 60 * 1_000_000_000

    // MARK: - Backup Settings

    /// Default number of Index.plist backups to retain.
    static let defaultBackupRetentionCount = 10

    /// Maximum number of backups allowed.
    static let maximumBackupRetentionCount = 50
}

