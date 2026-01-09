import SwiftUI
import KeyboardShortcuts

struct HotkeysSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    private let systemSettingsOpener: any SystemSettingsOpening

    init(systemSettingsOpener: any SystemSettingsOpening) {
        self.systemSettingsOpener = systemSettingsOpener
    }

    var body: some View {
        Form {
            Section {
                Text("Hotkeys are global. If a shortcut doesn’t work, it’s often due to macOS permissions or conflicts with another app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Aerial navigation") {
                LabeledContent("Next Aerial") {
                    KeyboardShortcuts.Recorder("", name: .nextAerial)
                }
                .help("Immediately switch to the next Aerial wallpaper.")

                LabeledContent("Next In Subcategory") {
                    KeyboardShortcuts.Recorder("", name: .nextInSubcategory)
                }
                .help("Advance within the current Aerial’s primary subcategory (deterministic).")

                LabeledContent("Exclude current aerial + Next") {
                    KeyboardShortcuts.Recorder("", name: .excludeCurrentSubcategoryAndNext)
                }
                .help("Exclude the current Aerial and immediately switch to the next eligible Aerial.")
            }

            Section("System controls") {
                LabeledContent("Pause / Continue") {
                    KeyboardShortcuts.Recorder("", name: .togglePause)
                }
                .help("Toggle scheduled rotation on or off.")

                LabeledContent("Go To Screensaver") {
                    KeyboardShortcuts.Recorder("", name: .goToScreensaver)
                }
                .help("Start the screensaver right away.")
            }

            Section("Permissions") {
                Text("If hotkeys don’t work, enable AerialFlow in these macOS privacy sections:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Open Input Monitoring…") {
                        _ = systemSettingsOpener.openInputMonitoringSettings()
                    }
                    Button("Open Accessibility…") {
                        _ = systemSettingsOpener.openAccessibilitySettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

