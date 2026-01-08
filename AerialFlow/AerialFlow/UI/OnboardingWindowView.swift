import SwiftUI

struct OnboardingWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AerialFlow setup")
                .font(.headline)

            Text("AerialFlow needs macOS to be configured for Aerial wallpapers so it can switch to the next video.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            SystemAccessStatusView(
                report: appState.systemAccessReport,
                onRefresh: { appState.refreshSystemAccessReport() }
            )

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
        .frame(width: 560, height: 360)
    }
}


