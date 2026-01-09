import Combine
import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: userDefaults)
            onSettingsChanged?(settings)
        }
    }

    /// Called after settings are persisted. This is where the owner can fan-out to coordinators, refresh probes, etc.
    var onSettingsChanged: (@MainActor (AppSettings) -> Void)?

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults, initialSettings: AppSettings) {
        self.userDefaults = userDefaults
        self.settings = initialSettings
    }
}

