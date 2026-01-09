import SwiftUI

struct OnboardingWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AerialFlow setup")
                .font(.headline)

            Text("AerialFlow needs macOS to be configured for Aerial wallpapers so it can switch to the next video. For Screen Saver, set it to Automatic so it follows the wallpaper.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            SystemAccessStatusView(
                report: appState.systemAccessReport,
                onRefresh: { appState.refreshSystemAccessReport() }
            )

            Divider()

            HStack(spacing: 10) {
                Button("Fix wallpaper configuration") {
                    Task {
                        await appState.nextAerial()
                        appState.refreshSystemAccessReport()
                    }
                }
                .disabled(appState.isBusy)

                Button("Open Wallpaper Settings") {
                    appState.openWallpaperSettings()
                }

                Button("Open Screen Saver Settings") {
                    appState.openScreenSaverSettings()
                }

                Spacer()
            }

            Divider()

            HStack {
                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 640, height: 420)
    }
}


