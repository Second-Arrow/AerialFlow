import SwiftUI

struct RotationSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Text("Schedule automatic background changes. Rotation pauses while your Mac sleeps or screens are off.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Rotation") {
                let rotationEnabledBinding = Binding(
                    get: { appState.settings.isRotationEnabled },
                    set: { appState.settings.isRotationEnabled = $0 }
                )

                Toggle("Enable scheduled rotation", isOn: rotationEnabledBinding)
                    .help("Automatically switch to the next Aerial on a schedule.")

                Toggle(
                    "Random mode",
                    isOn: Binding(
                        get: { appState.settings.randomMode },
                        set: { appState.settings.randomMode = $0 }
                    )
                )
                .help("Pick a random eligible Aerial instead of cycling in order. Some repeats may occur over time.")

                let minutesBinding = Binding<Int>(
                    get: { max(1, appState.settings.rotationIntervalSeconds / 60) },
                    set: { appState.settings.rotationIntervalSeconds = max(60, $0 * 60) }
                )

                LabeledContent("Interval") {
                    RotationIntervalControl(
                        minutes: minutesBinding,
                        minMinutes: 1,
                        sliderMaxMinutes: Constants.maximumRotationIntervalMinutes
                    )
                }
                .disabled(!appState.settings.isRotationEnabled)

                let resumeBehaviorBinding = Binding<AppSettings.SleepResumeBehavior>(
                    get: { appState.settings.sleepResumeBehavior },
                    set: { appState.settings.sleepResumeBehavior = $0 }
                )

                LabeledContent("After sleep / display off") {
                    Picker("", selection: resumeBehaviorBinding) {
                        Text("Use original time left")
                            .tag(AppSettings.SleepResumeBehavior.useOriginalTimeLeft)
                        Text("Immediately go to next Aerial")
                            .tag(AppSettings.SleepResumeBehavior.immediatelyGoToNextAerial)
                        Text("Restart the rotation timer")
                            .tag(AppSettings.SleepResumeBehavior.restartRotationTimer)
                    }
                    .labelsHidden()
                }
                .help("What to do when macOS wakes up or your displays turn back on.")

                Text("AerialFlow stores the remaining time when sleep/screen-off happens, then resumes based on this setting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

