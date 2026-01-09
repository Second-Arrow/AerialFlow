import SwiftUI
import UserNotifications

struct GeneralSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    private let systemSettingsOpener: any SystemSettingsOpening

    init(systemSettingsOpener: any SystemSettingsOpening) {
        self.systemSettingsOpener = systemSettingsOpener
    }

    var body: some View {
        Form {
            Section {
                Text("Control how AerialFlow runs in the background and how it interacts with macOS permissions and notifications.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                SystemAccessStatusView(
                    report: appState.systemAccessReport,
                    onRefresh: { appState.refreshSystemAccessReport() }
                )
            }

            Section("Startup") {
                let launchAtLoginBinding = Binding(
                    get: { appState.settings.launchAtLogin },
                    set: { appState.setLaunchAtLoginEnabled($0) }
                )

                Toggle("Launch at login", isOn: launchAtLoginBinding)
                    .help("Launch AerialFlow automatically after you sign in. macOS may require approval in Login Items.")

                if let message = appState.launchAtLoginErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                } else {
                    Text("Start AerialFlow automatically when you sign in.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Open Login Items…") {
                    _ = systemSettingsOpener.openLoginItemsSettings()
                }
                .help("Open System Settings where macOS asks you to approve AerialFlow as a login item.")
            }

            Section("Storage") {
                let excludedCleanupEnabledBinding = Binding(
                    get: { appState.settings.isExcludedAerialCleanupEnabled },
                    set: { appState.settings.isExcludedAerialCleanupEnabled = $0 }
                )

                Toggle("Automatically remove excluded Aerials", isOn: excludedCleanupEnabledBinding)
                    .help("Once a day, remove excluded Aerial .mov files from the storage location. This does not run while your Mac is asleep.")

                HStack(spacing: 10) {
                    Button("Clean Now") {
                        appState.cleanExcludedAerialsNow()
                    }
                    .disabled(appState.isCleaningExcludedAerials)
                    .help("Remove excluded Aerial .mov files now (even if the daily schedule is off).")

                    if appState.isCleaningExcludedAerials {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text("This affects downloaded video files only; it does not change your exclusions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                CheckForUpdatesView()
            }

            Section("Notifications") {
                HStack(alignment: .firstTextBaseline) {
                    Text("Status: \(notificationStatusText(appState.notificationAuthorizationStatus))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") {
                        Task { await appState.refreshNotificationAuthorizationStatus() }
                    }
                }

                HStack(spacing: 10) {
                    Button("Enable Notifications…") {
                        appState.requestNotificationAuthorization()
                    }
                    .disabled(appState.notificationAuthorizationStatus != .notDetermined)

                    Button("Open Notification Settings…") {
                        _ = systemSettingsOpener.openNotificationsSettings()
                    }
                }

                Text("Used to show an alert if a user-triggered action fails (for example: Next Aerial).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func notificationStatusText(_ status: UNAuthorizationStatus?) -> String {
        guard let status else { return "Unknown" }
        switch status {
        case .notDetermined: return "Not determined"
        case .denied: return "Denied"
        case .authorized: return "Allowed"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
}

