import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var snapshot: DiagnosticsSnapshot?
    @State private var snapshotErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Runtime")
                    .font(.headline)

                keyValueRow("Detected video dir", value: snapshot?.detectedVideoDirectory?.path)
                keyValueRow("Current .mov open", value: snapshot?.currentMovPath?.path)
                keyValueRow("Storage used", value: formattedStorageUsed(snapshot?.storageUsedBytes))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("State")
                    .font(.headline)

                keyValueRow("Index.plist", value: appState.settings.indexPlistURL.path)
                keyValueRow("Last applied asset ID", value: snapshot?.lastAssetID)
                keyValueRow("Last change", value: snapshot?.lastChangeDescription)
                keyValueRow("Next update", value: snapshot?.nextScheduledChangeDescription)
                keyValueRow("Last error", value: appState.lastErrorMessage)

                SettingsRow("Backup retention", labelWidth: 160) {
                    Text("\(appState.settings.backupRetentionCount)")
                        .foregroundStyle(.secondary)
                }
                .help("How many Index.plist backups AerialFlow keeps. Change this in Configuration > Advanced.")

                Text("Diagnostics are read-only. Adjust settings in the other tabs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Backups")
                    .font(.headline)

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

                Text("Backup retention can be changed in Configuration > Advanced.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let snapshotErrorMessage {
                Text(snapshotErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }
        }
        .task { await refresh() }
        .onChange(of: appState.settings.indexPlistURL) { _, _ in
            Task { await refresh() }
        }
        .onChange(of: appState.statusLine) { _, _ in
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
        SettingsRow(key, labelWidth: 160) {
            Text(value ?? "—")
                .foregroundStyle(value == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func formattedStorageUsed(_ bytes: Int64?) -> String? {
        guard let bytes else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}



