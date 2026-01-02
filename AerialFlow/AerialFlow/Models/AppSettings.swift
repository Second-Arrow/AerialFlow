import Foundation

/// User-configurable settings for AerialFlow.
///
/// Note: For Milestone 2 we load a snapshot at startup to configure the engine.
/// Settings UI wiring will come later.
struct AppSettings: Sendable, Equatable {
    /// Controls whether scheduled rotation is enabled (scheduler arrives in Milestone 5).
    var isRotationEnabled: Bool
    /// Rotation interval in seconds (scheduler arrives in Milestone 5).
    var rotationIntervalSeconds: Int
    var excludedCategoryIDs: Set<String>
    var randomMode: Bool
    var qualityPreference: VideoQualityPreference
    var downloadTimeout: TimeInterval
    var indexPlistURL: URL

    init(
        isRotationEnabled: Bool = true,
        rotationIntervalSeconds: Int = 600,
        excludedCategoryIDs: Set<String> = [],
        randomMode: Bool = false,
        qualityPreference: VideoQualityPreference = .prefer240fps,
        downloadTimeout: TimeInterval = 60,
        indexPlistURL: URL = WallpaperStoreEditor.defaultIndexPlistURL
    ) {
        self.isRotationEnabled = isRotationEnabled
        self.rotationIntervalSeconds = rotationIntervalSeconds
        self.excludedCategoryIDs = excludedCategoryIDs
        self.randomMode = randomMode
        self.qualityPreference = qualityPreference
        self.downloadTimeout = downloadTimeout
        self.indexPlistURL = indexPlistURL
    }
}

extension AppSettings {
    private enum Keys {
        static let isRotationEnabled = "AerialFlow.isRotationEnabled"
        static let rotationIntervalSeconds = "AerialFlow.rotationIntervalSeconds"
        static let excludedCategoryIDs = "AerialFlow.excludedCategoryIDs"
        static let randomMode = "AerialFlow.randomMode"
        static let qualityPreference = "AerialFlow.qualityPreference"
        static let downloadTimeout = "AerialFlow.downloadTimeout"
        static let indexPlistURL = "AerialFlow.indexPlistURL"
    }

    static func load(from userDefaults: UserDefaults = .standard) -> AppSettings {
        // Migration from legacy "pause" key (Milestone 2).
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

        let intervalSeconds = userDefaults.object(forKey: Keys.rotationIntervalSeconds) as? Int ?? 600
        let rotationIntervalSeconds = max(60, intervalSeconds)

        let excluded = Set(userDefaults.stringArray(forKey: Keys.excludedCategoryIDs) ?? [])
        let randomMode = userDefaults.bool(forKey: Keys.randomMode)

        let qualityRaw = userDefaults.string(forKey: Keys.qualityPreference)
        let quality = qualityRaw.flatMap(VideoQualityPreference.init(rawValue:)) ?? .prefer240fps

        let timeout = userDefaults.object(forKey: Keys.downloadTimeout) as? Double ?? 60

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
            excludedCategoryIDs: excluded,
            randomMode: randomMode,
            qualityPreference: quality,
            downloadTimeout: timeout,
            indexPlistURL: indexPlistURL
        )
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(isRotationEnabled, forKey: Keys.isRotationEnabled)
        userDefaults.set(rotationIntervalSeconds, forKey: Keys.rotationIntervalSeconds)
        userDefaults.set(Array(excludedCategoryIDs).sorted(), forKey: Keys.excludedCategoryIDs)
        userDefaults.set(randomMode, forKey: Keys.randomMode)
        userDefaults.set(qualityPreference.rawValue, forKey: Keys.qualityPreference)
        userDefaults.set(downloadTimeout, forKey: Keys.downloadTimeout)
        userDefaults.set(indexPlistURL.absoluteString, forKey: Keys.indexPlistURL)
    }
}

// MARK: - Core Protocol Conformance

extension AppSettings: AerialEngineSettings {}


