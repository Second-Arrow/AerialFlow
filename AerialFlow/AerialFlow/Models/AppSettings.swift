import Foundation

/// User-configurable settings for AerialFlow.
struct AppSettings: Sendable, Equatable {
    /// Controls whether scheduled rotation is enabled.
    var isRotationEnabled: Bool
    /// Rotation interval in seconds.
    var rotationIntervalSeconds: Int
    var launchAtLogin: Bool
    var excludedCategoryIDs: Set<String>
    var excludedSubcategoryIDs: Set<String>
    var randomMode: Bool
    var downloadTimeout: TimeInterval
    var indexPlistURL: URL
    var skipWhenDisplayOff: Bool
    var skipWhenScreensaverActive: Bool
    var skipAtLoginWindow: Bool
    /// Number of Index.plist backups to keep (oldest backups are pruned).
    var backupRetentionCount: Int

    init(
        isRotationEnabled: Bool = true,
        rotationIntervalSeconds: Int = Constants.defaultRotationIntervalSeconds,
        launchAtLogin: Bool = false,
        excludedCategoryIDs: Set<String> = [],
        excludedSubcategoryIDs: Set<String> = [],
        randomMode: Bool = false,
        downloadTimeout: TimeInterval = Constants.defaultDownloadTimeoutSeconds,
        indexPlistURL: URL = WallpaperStoreEditor.defaultIndexPlistURL,
        skipWhenDisplayOff: Bool = true,
        skipWhenScreensaverActive: Bool = true,
        skipAtLoginWindow: Bool = true,
        backupRetentionCount: Int = Constants.defaultBackupRetentionCount
    ) {
        self.isRotationEnabled = isRotationEnabled
        self.rotationIntervalSeconds = rotationIntervalSeconds
        self.launchAtLogin = launchAtLogin
        self.excludedCategoryIDs = excludedCategoryIDs
        self.excludedSubcategoryIDs = excludedSubcategoryIDs
        self.randomMode = randomMode
        self.downloadTimeout = downloadTimeout
        self.indexPlistURL = indexPlistURL
        self.skipWhenDisplayOff = skipWhenDisplayOff
        self.skipWhenScreensaverActive = skipWhenScreensaverActive
        self.skipAtLoginWindow = skipAtLoginWindow
        self.backupRetentionCount = Self.validateBackupRetentionCount(backupRetentionCount)
    }
}

extension AppSettings {
    private enum Keys {
        static let isRotationEnabled = "AerialFlow.isRotationEnabled"
        static let rotationIntervalSeconds = "AerialFlow.rotationIntervalSeconds"
        static let launchAtLogin = "AerialFlow.launchAtLogin"
        static let excludedCategoryIDs = "AerialFlow.excludedCategoryIDs"
        static let excludedSubcategoryIDs = "AerialFlow.excludedSubcategoryIDs"
        static let randomMode = "AerialFlow.randomMode"
        static let downloadTimeout = "AerialFlow.downloadTimeout"
        static let indexPlistURL = "AerialFlow.indexPlistURL"
        static let skipWhenDisplayOff = "AerialFlow.skipWhenDisplayOff"
        static let skipWhenScreensaverActive = "AerialFlow.skipWhenScreensaverActive"
        static let skipAtLoginWindow = "AerialFlow.skipAtLoginWindow"
        static let backupRetentionCount = "AerialFlow.backupRetentionCount"
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
        let randomMode = userDefaults.bool(forKey: Keys.randomMode)

        let timeout = userDefaults.object(forKey: Keys.downloadTimeout) as? Double ?? Constants.defaultDownloadTimeoutSeconds

        let skipWhenDisplayOff = userDefaults.object(forKey: Keys.skipWhenDisplayOff) as? Bool ?? true
        let skipWhenScreensaverActive = userDefaults.object(forKey: Keys.skipWhenScreensaverActive) as? Bool ?? true
        let skipAtLoginWindow = userDefaults.object(forKey: Keys.skipAtLoginWindow) as? Bool ?? true
        let backupRetentionRaw = userDefaults.object(forKey: Keys.backupRetentionCount) as? Int ?? Constants.defaultBackupRetentionCount
        let backupRetentionCount = validateBackupRetentionCount(backupRetentionRaw)

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
            randomMode: randomMode,
            downloadTimeout: timeout,
            indexPlistURL: indexPlistURL,
            skipWhenDisplayOff: skipWhenDisplayOff,
            skipWhenScreensaverActive: skipWhenScreensaverActive,
            skipAtLoginWindow: skipAtLoginWindow,
            backupRetentionCount: backupRetentionCount
        )
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(isRotationEnabled, forKey: Keys.isRotationEnabled)
        userDefaults.set(rotationIntervalSeconds, forKey: Keys.rotationIntervalSeconds)
        userDefaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        userDefaults.set(Array(excludedCategoryIDs).sorted(), forKey: Keys.excludedCategoryIDs)
        userDefaults.set(Array(excludedSubcategoryIDs).sorted(), forKey: Keys.excludedSubcategoryIDs)
        userDefaults.set(randomMode, forKey: Keys.randomMode)
        userDefaults.set(downloadTimeout, forKey: Keys.downloadTimeout)
        userDefaults.set(indexPlistURL.absoluteString, forKey: Keys.indexPlistURL)
        userDefaults.set(skipWhenDisplayOff, forKey: Keys.skipWhenDisplayOff)
        userDefaults.set(skipWhenScreensaverActive, forKey: Keys.skipWhenScreensaverActive)
        userDefaults.set(skipAtLoginWindow, forKey: Keys.skipAtLoginWindow)
        userDefaults.set(Self.validateBackupRetentionCount(backupRetentionCount), forKey: Keys.backupRetentionCount)
    }

    private static func validateBackupRetentionCount(_ value: Int) -> Int {
        min(Constants.maximumBackupRetentionCount, max(1, value))
    }
}

// MARK: - Core Protocol Conformance

extension AppSettings: AerialEngineSettings {}
extension AppSettings: RunGuardSettings {}


