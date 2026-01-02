import Foundation

/// UserDefaults-backed persistence for `AerialEngine` runtime state.
actor UserDefaultsEngineStateStore: AerialEngineStateStore {
    private let userDefaults: UserDefaults

    private enum Keys {
        static let lastAssetID = "AerialFlow.lastAssetID"
        static let lastChange = "AerialFlow.lastChange"
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func getLastAssetID() async -> String? {
        userDefaults.string(forKey: Keys.lastAssetID)
    }

    func setLastAssetID(_ id: String?) async {
        if let id {
            userDefaults.set(id, forKey: Keys.lastAssetID)
        } else {
            userDefaults.removeObject(forKey: Keys.lastAssetID)
        }
    }

    func getLastChange() async -> Date? {
        userDefaults.object(forKey: Keys.lastChange) as? Date
    }

    func setLastChange(_ date: Date?) async {
        if let date {
            userDefaults.set(date, forKey: Keys.lastChange)
        } else {
            userDefaults.removeObject(forKey: Keys.lastChange)
        }
    }
}


