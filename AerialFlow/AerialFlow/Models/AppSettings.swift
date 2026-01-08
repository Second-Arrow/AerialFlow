import Foundation

/// User-configurable settings for AerialFlow.
struct AppSettings: Sendable, Equatable {
    enum SleepResumeBehavior: String, CaseIterable, Sendable, Equatable {
        /// Continue the schedule using the remaining time at the moment sleep/screen-off began.
        case useOriginalTimeLeft
        /// Trigger the next Aerial immediately after wake/screen-on.
        case immediatelyGoToNextAerial
        /// Restart the rotation interval from wake/screen-on.
        case restartRotationTimer
    }

    /// Controls whether scheduled rotation is enabled.
    var isRotationEnabled: Bool
    /// Rotation interval in seconds.
    var rotationIntervalSeconds: Int
    var launchAtLogin: Bool
    var excludedCategoryIDs: Set<String>
    var excludedSubcategoryIDs: Set<String>
    var excludedAssetIDs: Set<String>
    /// Controls whether AerialFlow automatically removes excluded `.mov` files from the storage location.
    /// Default: off.
    var isExcludedAerialCleanupEnabled: Bool
    var randomMode: Bool
    var downloadTimeout: TimeInterval
    var indexPlistURL: URL
    /// Behavior to use when the system wakes up (or screens turn back on) after AerialFlow hibernates.
    var sleepResumeBehavior: SleepResumeBehavior
    /// Number of Index.plist backups to keep (oldest backups are pruned).
    var backupRetentionCount: Int
    /// Controls whether AerialFlow filters Aerials based on brightness outside an allowed light window.
    /// Default: off.
    var isLightSensitiveFilteringEnabled: Bool
    /// Minutes since midnight (0...1440). When current time is within [start, end], light Aerials are allowed.
    /// Default: 10:00.
    var allowedLightStartMinutes: Int
    /// Minutes since midnight (0...1440). When current time is within [start, end], light Aerials are allowed.
    /// Default: 18:00.
    var allowedLightEndMinutes: Int
    /// Brightness threshold (0.0...1.0). Outside the allowed light window, only assets with brightness < threshold are considered eligible.
    /// Default: 0.5.
    var lightSensitivity: Double

    init(
        isRotationEnabled: Bool = true,
        rotationIntervalSeconds: Int = Constants.defaultRotationIntervalSeconds,
        launchAtLogin: Bool = false,
        excludedCategoryIDs: Set<String> = [],
        excludedSubcategoryIDs: Set<String> = [],
        excludedAssetIDs: Set<String> = [],
        isExcludedAerialCleanupEnabled: Bool = false,
        randomMode: Bool = false,
        downloadTimeout: TimeInterval = Constants.defaultDownloadTimeoutSeconds,
        indexPlistURL: URL = WallpaperStoreEditor.defaultIndexPlistURL,
        sleepResumeBehavior: SleepResumeBehavior = .useOriginalTimeLeft,
        backupRetentionCount: Int = Constants.defaultBackupRetentionCount,
        isLightSensitiveFilteringEnabled: Bool = false,
        allowedLightStartMinutes: Int = 10 * 60,
        allowedLightEndMinutes: Int = 18 * 60,
        lightSensitivity: Double = 0.5
    ) {
        self.isRotationEnabled = isRotationEnabled
        self.rotationIntervalSeconds = rotationIntervalSeconds
        self.launchAtLogin = launchAtLogin
        self.excludedCategoryIDs = excludedCategoryIDs
        self.excludedSubcategoryIDs = excludedSubcategoryIDs
        self.excludedAssetIDs = excludedAssetIDs
        self.isExcludedAerialCleanupEnabled = isExcludedAerialCleanupEnabled
        self.randomMode = randomMode
        self.downloadTimeout = downloadTimeout
        self.indexPlistURL = indexPlistURL
        self.sleepResumeBehavior = sleepResumeBehavior
        self.backupRetentionCount = Self.validateBackupRetentionCount(backupRetentionCount)
        self.isLightSensitiveFilteringEnabled = isLightSensitiveFilteringEnabled
        self.allowedLightStartMinutes = Self.validateMinutesSinceMidnight(allowedLightStartMinutes)
        self.allowedLightEndMinutes = Self.validateMinutesSinceMidnight(allowedLightEndMinutes)
        self.lightSensitivity = Self.validateUnitInterval(lightSensitivity)
    }
}

extension AppSettings {
    private enum Keys {
        static let isRotationEnabled = "AerialFlow.isRotationEnabled"
        static let rotationIntervalSeconds = "AerialFlow.rotationIntervalSeconds"
        static let launchAtLogin = "AerialFlow.launchAtLogin"
        static let excludedCategoryIDs = "AerialFlow.excludedCategoryIDs"
        static let excludedSubcategoryIDs = "AerialFlow.excludedSubcategoryIDs"
        static let excludedAssetIDs = "AerialFlow.excludedAssetIDs"
        static let isExcludedAerialCleanupEnabled = "AerialFlow.isExcludedAerialCleanupEnabled"
        static let randomMode = "AerialFlow.randomMode"
        static let downloadTimeout = "AerialFlow.downloadTimeout"
        static let indexPlistURL = "AerialFlow.indexPlistURL"
        static let sleepResumeBehavior = "AerialFlow.sleepResumeBehavior"
        static let backupRetentionCount = "AerialFlow.backupRetentionCount"
        static let isLightSensitiveFilteringEnabled = "AerialFlow.isLightSensitiveFilteringEnabled"
        static let allowedLightStartMinutes = "AerialFlow.allowedLightStartMinutes"
        static let allowedLightEndMinutes = "AerialFlow.allowedLightEndMinutes"
        static let lightSensitivity = "AerialFlow.lightSensitivity"
    }

    static func load(from userDefaults: UserDefaults = .standard) -> AppSettings {
        // Migration from legacy "pause" key.
        // If the old key exists and the new one does not, map pause -> rotationEnabled.
        let legacyPausedKey = "AerialFlow.isPaused"
        let hasLegacyPaused = userDefaults.object(forKey: legacyPausedKey) != nil
        let hasNewRotationEnabled = userDefaults.object(forKey: Keys.isRotationEnabled) != nil
        if hasLegacyPaused, !hasNewRotationEnabled {
            let wasPaused = userDefaults.bool(forKey: legacyPausedKey)
            let isRotationEnabled = !wasPaused
            userDefaults.set(isRotationEnabled, forKey: Keys.isRotationEnabled)
        }

        let isRotationEnabled = userDefaults.object(forKey: Keys.isRotationEnabled) as? Bool ?? true

        let intervalSeconds = userDefaults.object(forKey: Keys.rotationIntervalSeconds) as? Int ?? Constants.defaultRotationIntervalSeconds
        let rotationIntervalSeconds = max(Constants.minimumRotationIntervalSeconds, intervalSeconds)

        let launchAtLogin = userDefaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false

        let excluded = Set(userDefaults.stringArray(forKey: Keys.excludedCategoryIDs) ?? [])
        let excludedSubcategories = Set(userDefaults.stringArray(forKey: Keys.excludedSubcategoryIDs) ?? [])
        let excludedAssets = Set(userDefaults.stringArray(forKey: Keys.excludedAssetIDs) ?? [])
        let isExcludedAerialCleanupEnabled = userDefaults.object(forKey: Keys.isExcludedAerialCleanupEnabled) as? Bool ?? false
        let randomMode = userDefaults.bool(forKey: Keys.randomMode)

        let timeout = userDefaults.object(forKey: Keys.downloadTimeout) as? Double ?? Constants.defaultDownloadTimeoutSeconds

        let sleepResumeBehaviorRaw = userDefaults.string(forKey: Keys.sleepResumeBehavior)
        let sleepResumeBehavior = SleepResumeBehavior(rawValue: sleepResumeBehaviorRaw ?? "") ?? .useOriginalTimeLeft
        let backupRetentionRaw = userDefaults.object(forKey: Keys.backupRetentionCount) as? Int ?? Constants.defaultBackupRetentionCount
        let backupRetentionCount = validateBackupRetentionCount(backupRetentionRaw)

        let isLightSensitiveFilteringEnabled = userDefaults.object(forKey: Keys.isLightSensitiveFilteringEnabled) as? Bool ?? false
        let allowedLightStartRaw = userDefaults.object(forKey: Keys.allowedLightStartMinutes) as? Int ?? (10 * 60)
        let allowedLightEndRaw = userDefaults.object(forKey: Keys.allowedLightEndMinutes) as? Int ?? (18 * 60)
        let lightSensitivityRaw = userDefaults.object(forKey: Keys.lightSensitivity) as? Double ?? 0.5
        let allowedLightStartMinutes = validateMinutesSinceMidnight(allowedLightStartRaw)
        let allowedLightEndMinutes = validateMinutesSinceMidnight(allowedLightEndRaw)
        let lightSensitivity = validateUnitInterval(lightSensitivityRaw)

        let indexPlistURL: URL
        if let urlString = userDefaults.string(forKey: Keys.indexPlistURL),
           let url = URL(string: urlString) {
            indexPlistURL = url
        } else {
            indexPlistURL = WallpaperStoreEditor.defaultIndexPlistURL
        }

        return AppSettings(
            isRotationEnabled: isRotationEnabled,
            rotationIntervalSeconds: rotationIntervalSeconds,
            launchAtLogin: launchAtLogin,
            excludedCategoryIDs: excluded,
            excludedSubcategoryIDs: excludedSubcategories,
            excludedAssetIDs: excludedAssets,
            isExcludedAerialCleanupEnabled: isExcludedAerialCleanupEnabled,
            randomMode: randomMode,
            downloadTimeout: timeout,
            indexPlistURL: indexPlistURL,
            sleepResumeBehavior: sleepResumeBehavior,
            backupRetentionCount: backupRetentionCount,
            isLightSensitiveFilteringEnabled: isLightSensitiveFilteringEnabled,
            allowedLightStartMinutes: allowedLightStartMinutes,
            allowedLightEndMinutes: allowedLightEndMinutes,
            lightSensitivity: lightSensitivity
        )
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(isRotationEnabled, forKey: Keys.isRotationEnabled)
        userDefaults.set(rotationIntervalSeconds, forKey: Keys.rotationIntervalSeconds)
        userDefaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        userDefaults.set(Array(excludedCategoryIDs).sorted(), forKey: Keys.excludedCategoryIDs)
        userDefaults.set(Array(excludedSubcategoryIDs).sorted(), forKey: Keys.excludedSubcategoryIDs)
        userDefaults.set(Array(excludedAssetIDs).sorted(), forKey: Keys.excludedAssetIDs)
        userDefaults.set(isExcludedAerialCleanupEnabled, forKey: Keys.isExcludedAerialCleanupEnabled)
        userDefaults.set(randomMode, forKey: Keys.randomMode)
        userDefaults.set(downloadTimeout, forKey: Keys.downloadTimeout)
        userDefaults.set(indexPlistURL.absoluteString, forKey: Keys.indexPlistURL)
        userDefaults.set(sleepResumeBehavior.rawValue, forKey: Keys.sleepResumeBehavior)
        userDefaults.set(Self.validateBackupRetentionCount(backupRetentionCount), forKey: Keys.backupRetentionCount)
        userDefaults.set(isLightSensitiveFilteringEnabled, forKey: Keys.isLightSensitiveFilteringEnabled)
        userDefaults.set(Self.validateMinutesSinceMidnight(allowedLightStartMinutes), forKey: Keys.allowedLightStartMinutes)
        userDefaults.set(Self.validateMinutesSinceMidnight(allowedLightEndMinutes), forKey: Keys.allowedLightEndMinutes)
        userDefaults.set(Self.validateUnitInterval(lightSensitivity), forKey: Keys.lightSensitivity)

        // Remove legacy keys that no longer map to any current setting.
        userDefaults.removeObject(forKey: "AerialFlow.skipWhenDisplayOff")
        userDefaults.removeObject(forKey: "AerialFlow.skipWhenScreensaverActive")
        userDefaults.removeObject(forKey: "AerialFlow.skipAtLoginWindow")
    }

    private static func validateBackupRetentionCount(_ value: Int) -> Int {
        min(Constants.maximumBackupRetentionCount, max(1, value))
    }

    private static func validateMinutesSinceMidnight(_ value: Int) -> Int {
        min(24 * 60, max(0, value))
    }

    private static func validateUnitInterval(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

// MARK: - Core Protocol Conformance

extension AppSettings: AerialEngineSettings {}


