import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var snapshot: AppState.DiagnosticsSnapshot?
    @State private var snapshotErrorMessage: String?

    var body: some View {
        Form {
            Section("Runtime") {
                keyValueRow("Detected video dir", value: snapshot?.detectedVideoDirectory?.path)
                keyValueRow("Current .mov open", value: snapshot?.currentMovPath?.path)
            }

            Section("State") {
                keyValueRow("Index.plist", value: appState.settings.indexPlistURL.path)
                keyValueRow("Last applied asset ID", value: snapshot?.lastAssetID)
                keyValueRow("Last change", value: snapshot?.lastChangeDescription)
                keyValueRow("Last error", value: appState.lastErrorMessage)
            }

            Section("Backups") {
                Stepper(
                    value: Binding(
                        get: { appState.settings.backupRetentionCount },
                        set: { appState.settings.backupRetentionCount = $0 }
                    ),
                    in: 1...50,
                    step: 1
                ) {
                    Text("Keep last \(appState.settings.backupRetentionCount) backups")
                }

                if let count = snapshot?.backupCount {
                    Text("Found \(count) backups next to Index.plist.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Loading backups…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let backupNames = snapshot?.recentBackupFileNames, !backupNames.isEmpty {
                    DisclosureGroup("Most recent backups") {
                        ForEach(backupNames, id: \.self) { name in
                            Text(name)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let snapshotErrorMessage {
                Text(snapshotErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }
        }
        .task { await refresh() }
        .onChange(of: appState.settings.indexPlistURL) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        do {
            let s = try await appState.loadDiagnosticsSnapshot()
            snapshot = s
            snapshotErrorMessage = nil
        } catch {
            snapshot = nil
            snapshotErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func keyValueRow(_ key: String, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .frame(width: 160, alignment: .leading)
            Spacer()
            Text(value ?? "—")
                .foregroundStyle(value == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .multilineTextAlignment(.trailing)
        }
    }
}


