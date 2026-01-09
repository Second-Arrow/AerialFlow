import SwiftUI

struct FilteringSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Text("Optionally prefer darker Aerials outside a time window, based on each Aerial’s preview-image brightness.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Light-sensitive filtering") {
                let enabledBinding = Binding(
                    get: { appState.settings.isLightSensitiveFilteringEnabled },
                    set: { appState.settings.isLightSensitiveFilteringEnabled = $0 }
                )

                Toggle("Enable light-sensitive filtering", isOn: enabledBinding)
                    .help("Outside the allowed light window, AerialFlow prefers darker Aerials.")

                LabeledContent("Light allowed") {
                    TimeRangeSlider(
                        title: "",
                        startMinutes: Binding(
                            get: { appState.settings.allowedLightStartMinutes },
                            set: { appState.settings.allowedLightStartMinutes = $0 }
                        ),
                        endMinutes: Binding(
                            get: { appState.settings.allowedLightEndMinutes },
                            set: { appState.settings.allowedLightEndMinutes = $0 }
                        ),
                        range: 0...(24 * 60),
                        step: 5
                    )
                    .frame(maxWidth: 360)
                }
                .disabled(!appState.settings.isLightSensitiveFilteringEnabled)

                LabeledContent("Sensitivity") {
                    let sensitivityBinding = Binding<Double>(
                        get: { appState.settings.lightSensitivity },
                        set: { appState.settings.lightSensitivity = $0 }
                    )

                    HStack(spacing: 10) {
                        Slider(value: sensitivityBinding, in: 0...1, step: 0.01)
                            .frame(width: 260)
                        Text(sensitivityBinding.wrappedValue.formatted(.number.precision(.fractionLength(2))))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
                .disabled(!appState.settings.isLightSensitiveFilteringEnabled)
                .help("Brightness threshold (0–1). Outside the allowed window, only Aerials below this value are eligible.")

                if appState.settings.isLightSensitiveFilteringEnabled, appState.settings.lightSensitivity < 0.15 {
                    Text("Tip: very low sensitivity values (below 0.15) can be too strict and may not find any suitable Aerials.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

