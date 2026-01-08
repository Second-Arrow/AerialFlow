import SwiftUI

struct CheckForUpdatesView: View {
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Version: \(AppVersion.displayString)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle("Check for updates automatically", isOn: $updaterViewModel.automaticallyChecksForUpdates.animation())

            if updaterViewModel.automaticallyChecksForUpdates {
                Picker("Update check interval", selection: $updaterViewModel.updateCheckInterval) {
                    Text("Daily").tag(TimeInterval(86_400))
                    Text("Weekly").tag(TimeInterval(604_800))
                    Text("Monthly").tag(TimeInterval(2_629_800))
                }
                .labelsHidden()
            }

            Button("Check for Updates…") {
                updaterViewModel.checkForUpdates()
            }
            .disabled(!updaterViewModel.canCheckForUpdates)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum AppVersion {
    static var displayString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (v?, b?) where !v.isEmpty && !b.isEmpty:
            return "\(v) (\(b))"
        case let (v?, _) where !v.isEmpty:
            return v
        case let (_, b?) where !b.isEmpty:
            return b
        default:
            return "Unknown"
        }
    }
}


