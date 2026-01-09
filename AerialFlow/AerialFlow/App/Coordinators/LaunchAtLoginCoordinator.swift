import Foundation

/// Owns Launch-at-login orchestration: reconciliation against system state and user-initiated enable/disable handling.
struct LaunchAtLoginCoordinator: Sendable {
    struct Update: Sendable, Equatable {
        let launchAtLoginEnabled: Bool
        let errorMessage: String?
    }

    private let manager: any LaunchAtLoginManaging

    init(manager: any LaunchAtLoginManaging) {
        self.manager = manager
    }

    /// Mirrors system state into the settings model (system is the source of truth).
    func reconciledSettingValue() -> Bool {
        switch manager.status() {
        case .enabled:
            return true
        case .disabled, .requiresApproval:
            return false
        }
    }

    /// Handles a user-initiated toggle attempt and returns the desired settings update.
    func setLaunchAtLoginEnabled(_ enabled: Bool, previousSettingValue: Bool) -> Update {
        do {
            if enabled {
                try manager.register()
            } else {
                try manager.unregister()
            }
        } catch {
            return Update(
                launchAtLoginEnabled: previousSettingValue,
                errorMessage: failureMessage(for: error)
            )
        }

        // ServiceManagement may require the user to approve the login item.
        switch manager.status() {
        case .enabled:
            return Update(launchAtLoginEnabled: true, errorMessage: nil)
        case .disabled:
            if enabled {
                return Update(
                    launchAtLoginEnabled: previousSettingValue,
                    errorMessage: failureMessage(for: nil)
                )
            } else {
                return Update(launchAtLoginEnabled: false, errorMessage: nil)
            }
        case .requiresApproval:
            return Update(
                launchAtLoginEnabled: previousSettingValue,
                errorMessage: "macOS requires approval. Enable AerialFlow in System Settings > General > Login Items."
            )
        }
    }

    private func failureMessage(for error: Error?) -> String {
        if let error {
            return "Couldn’t update Launch at login: \(error.localizedDescription). You can also enable it in System Settings > General > Login Items."
        }
        return "Couldn’t enable Launch at login. You can enable it in System Settings > General > Login Items."
    }
}

