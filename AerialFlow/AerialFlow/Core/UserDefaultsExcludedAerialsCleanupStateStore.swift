import Foundation

/// UserDefaults-backed persistence for excluded-aerial cleanup scheduler state.
actor UserDefaultsExcludedAerialsCleanupStateStore: ExcludedAerialsCleanupStateStoring {
    private let userDefaults: UserDefaults

    private enum Keys {
        static let autoCleanupEnabledSince = "AerialFlow.excludedAerialCleanup.enabledSince"
        static let lastAutoCleanupRunDate = "AerialFlow.excludedAerialCleanup.lastAutoRunDate"
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func getAutoCleanupEnabledSince() async -> Date? {
        userDefaults.object(forKey: Keys.autoCleanupEnabledSince) as? Date
    }

    func setAutoCleanupEnabledSince(_ date: Date?) async {
        if let date {
            userDefaults.set(date, forKey: Keys.autoCleanupEnabledSince)
        } else {
            userDefaults.removeObject(forKey: Keys.autoCleanupEnabledSince)
        }
    }

    func getLastAutoCleanupRunDate() async -> Date? {
        userDefaults.object(forKey: Keys.lastAutoCleanupRunDate) as? Date
    }

    func setLastAutoCleanupRunDate(_ date: Date?) async {
        if let date {
            userDefaults.set(date, forKey: Keys.lastAutoCleanupRunDate)
        } else {
            userDefaults.removeObject(forKey: Keys.lastAutoCleanupRunDate)
        }
    }
}


