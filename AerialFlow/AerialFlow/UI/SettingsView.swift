import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Toggle(
                "Paused",
                isOn: Binding(
                    get: { appState.isPaused },
                    set: { appState.setPaused($0) }
                )
            )

            Text("“Next Aerial” is currently disabled (UI-only scaffolding).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360)
    }
}

